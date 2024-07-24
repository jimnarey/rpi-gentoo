clean:
	rm -rf pi-rt-kernel/build

build:
	docker build -t pi-rt-kernel ./pi-rt-kernel

run:
	@mkdir -p pi-rt-kernel/build
	docker run --rm -it -v $$(pwd)/pi-rt-kernel/build:/build -u ubuntu pi-rt-kernel