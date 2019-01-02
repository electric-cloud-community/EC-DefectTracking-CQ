#
# Makefile responsible for building the EC-DefectTracking-CQ plugin
#
# Copyright (c) 2005-2012 Electric Cloud, Inc.
# All rights reserved

SRCTOP=..
include $(SRCTOP)/build/vars.mak

build: buildJavaPlugin package

unittest:

systemtest: start-selenium test-setup test-run stop-selenium

NTESTFILES  ?= systemtest

test-setup:
	$(INSTALL_PLUGINS) EC-DefectTracking EC-DefectTracking-CQ

test-run: systemtest-run

include $(SRCTOP)/build/rules.mak

test: build install promote

install:
	ectool installPlugin ../../../out/common/nimbus/EC-DefectTracking-CQ/EC-DefectTracking-CQ.jar
 
promote:
	ectool promotePlugin EC-DefectTracking-CQ
