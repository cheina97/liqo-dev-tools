TAG:=v0.0.3

build:
	docker build -t localhost:5001/liqo/dev-networkplayground:$(TAG) .
push: build
	docker push localhost:5001/liqo/dev-networkplayground:$(TAG)