.MAIN: gensymlink

gensymlink:
	if [ ! -d ./bin ]; then mkdir bin; fi
	chmod 777 -R *
	./utils/gensymlink.sh