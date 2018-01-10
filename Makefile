# This is a root level Makefile that is primarily used by the CI system to
# trigger builds using Docker images (for anything involving non-standard
# tools like OpenModelica).  The goal is that anybody should be able to use
# this Makefile to build the book on any machine that has Docker installed
# on it.
#
# N.B. - Any requires credentials are assumed to be provided by environment
# variables and should *not* be provided here.

BUILDER_IMAGE = mtiller/book-builder
S3BUCKET = beta.book.xogeny.com

S3CMD = s3cmd $(S3FLAGS)
SYNC = $(S3CMD) sync -P -F
S3MODIFY = $(S3CMD) modify

RUN = docker run -v `pwd`:/opt/MBE/ModelicaBook -i -t $(BUILDER_IMAGE)
GEN_RUN = docker run -v `pwd`:/opt/MBE/ModelicaBook -w /opt/MBE/ModelicaBook/generator -i -t $(BUILDER_IMAGE)
GPUB_RUN = docker run -v `pwd`:/opt/MBE/ModelicaBook -w /opt/MBE/ModelicaBook/generator/dist -e "AWS_ACCESS_KEY_ID=$(AWS_ACCESS_KEY)" -e "AWS_SECRET_KEY=$(AWS_SECRET_KEY)" -i -t $(BUILDER_IMAGE)
EPUB_RUN = docker run -v `pwd`:/opt/MBE/ModelicaBook -w /opt/MBE/ModelicaBook/text/build -e "AWS_ACCESS_KEY_ID=$(AWS_ACCESS_KEY)" -e "AWS_SECRET_KEY=$(AWS_SECRET_KEY)" -i -t $(BUILDER_IMAGE)
SERVE_RUN = docker run -v `pwd`:/opt/MBE/ModelicaBook -w /opt/MBE/ModelicaBook/text/build/dirhtml -p 5001:5001 -i -t $(BUILDER_IMAGE)

.PHONY: all deploy specs results dirhtml ebooks api publish_server publish_web serve

all: specs results dirhtml ebooks pdfs site

deploy: api publish_server publish_web publish_ebooks

deps:
	#docker pull $(BUILDER_IMAGE)

specs: deps
	$(RUN) make specs

results: deps
	$(RUN) make results

dirhtml: deps
	$(RUN) make dirhtml

json: deps
	$(RUN) make json

ebooks: deps
	$(RUN) make ebooks

pdfs: deps
	$(RUN) make pdf pdf-a4

site: deps
	$(GEN_RUN) yarn install
	$(GEN_RUN) yarn build

serve: dirhtml
	$(SERVE_RUN) serve -p 5001

# N.B. - This step can only be run by somebody who has access to the Xogeny private packages required to build the
# API.
api:
	- rm -rf api/models
	- mkdir api/models
	tar zxf text/results/exes.tar.gz --directory api/models
	(cd api; npm install -g dockergen && npm run image)

# This target requires the DOCKER_* environment variables to be set
publish_server:
	docker login -e $(DOCKER_EMAIL) -u $(DOCKER_USER) -p $(DOCKER_PASS)
	docker push $(BUILDER_IMAGE)

# This target requires the AWS_*_KEY environment variables to be set
publish_web:
	$(GPUB_RUN) sh -c '$(SYNC) * s3://$(S3BUCKET)/'
	$(GPUB_RUN) sh -c '$(S3MODIFY) -m text/css s3://$(S3BUCKET)/_static/semantic/*.css'
	$(GPUB_RUN) sh -c '$(S3MODIFY) -m text/css s3://$(S3BUCKET)/_static/*.css'
	$(GPUB_RUN) sh -c '$(S3MODIFY) -m text/css s3://$(S3BUCKET)/*.css'

set_cache_headers:
	-$(GPUB_RUN) sh -c '$(S3MODIFY) --recursive --add-header="Cache-Control:max-age=60" s3://$(S3BUCKET)/_static'
	-$(GPUB_RUN) sh -c '$(S3MODIFY) --recursive --add-header="Cache-Control:max-age=60" s3://$(S3BUCKET)/front'
	-$(GPUB_RUN) sh -c '$(S3MODIFY) --recursive --add-header="Cache-Control:max-age=60" s3://$(S3BUCKET)/behavior'
	-$(GPUB_RUN) sh -c '$(S3MODIFY) --recursive --add-header="Cache-Control:max-age=60" s3://$(S3BUCKET)/components'

publish_ebooks:
	-mkdir text/build/ebooks
	cp text/build/epub/ModelicaByExample.epub text/build/ebooks/ModelicaByExample-`git hash-object text/build/epub/ModelicaByExample.epub`.epub
	cp text/build/mobi/ModelicaByExample.mobi text/build/ebooks/ModelicaByExample-`git hash-object text/build/mobi/ModelicaByExample.mobi`.mobi
	cp text/build/latex/ModelicaByExample.pdf text/build/ebooks/ModelicaByExample-Letter-`git hash-object text/build/latex/ModelicaByExample.pdf`.pdf
	cp text/build/latex-a4/ModelicaByExample.pdf text/build/ebooks/ModelicaByExample-A4-`git hash-object text/build/latex-a4/ModelicaByExample.pdf`.pdf
	$(EPUB_RUN) sh -c '$(SYNC) ebooks/* s3://$(S3BUCKET)/eBooks/'
	$(GPUB_RUN) sh -c '$(S3MODIFY) -m application/epub+zip s3://$(S3BUCKET)/eBooks/*.epub'
	$(GPUB_RUN) sh -c '$(S3MODIFY) -m application/x-mobipocket s3://$(S3BUCKET)/eBooks/*.mobi'
	$(GPUB_RUN) sh -c '$(S3MODIFY) -m application/pdf s3://$(S3BUCKET)/eBooks/*.pdf'
