.MAIN: gensymlink

gensymlink:
	if [ ! -d ./bin ]; then mkdir bin; fi
	chmod -R 777 *
	./utils/gensymlink.sh