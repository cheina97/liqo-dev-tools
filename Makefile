.MAIN: gensymlink

gensymlink:
	if [ ! -d ./bin ]; then mkdir bin; fi
	./utils/gensymlink.sh