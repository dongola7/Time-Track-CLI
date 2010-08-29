VERSION=$(shell ./time_track.tcl version)
ARCHIVE=time-track-cli-$(VERSION).tar.gz

Portfile: Portfile.template $(ARCHIVE)
	sed 's/%VERSION%/$(VERSION)/' Portfile.template | \
	sed 's/%MD5%/$(shell openssl md5 < $(ARCHIVE))/' | \
	sed 's/%SHA1%/$(shell openssl sha1 < $(ARCHIVE))/' | \
	sed 's/%RMD160%/$(shell openssl rmd160 < $(ARCHIVE))/' > $@

$(ARCHIVE): time_track.tcl post-stop.sample README.html
	tar -czf $@ $^

distribute: Portfile $(ARCHIVE)
	curl -T $(ARCHIVE) ftp://$(shell cat ftp_login)@the-blair.com/www/sw/time-track-cli/

README.html: README.textile
	redcloth < $^ > $@

clean:
	rm -rf $(ARCHIVE) Portfile README.html
