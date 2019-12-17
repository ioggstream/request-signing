#
# Makefile for building ietf documents using
# Martin Thomson docker image.
#
# You can run the image like the following:
#
# $ docker run -ti --rm -v $PWD:/code -w /code --entrypoint /bin/sh martinthomson/i-d-template
#
# It then prompts you to a shell inside the container where you can run
#
# $ make
#
LIBDIR := lib
include $(LIBDIR)/main.mk

$(LIBDIR)/main.mk:
ifneq (,$(shell grep "path *= *$(LIBDIR)" .gitmodules 2>/dev/null))
	git submodule sync
	git submodule update $(CLONE_ARGS) --init
else
	git clone -q --depth 10 $(CLONE_ARGS) \
	    -b master https://github.com/martinthomson/i-d-template $(LIBDIR)
endif

