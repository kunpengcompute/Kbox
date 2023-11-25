all:
	go get -d -v ./...
	CGO_CFLAGS="-fstack-protector-strong -D_FORTIFY_SOURCE=2 -O2" go install -buildmode=pie -ldflags "-s -linkmode 'external' -extldflags '-Wl,-z,now'" ./cmd/*

# To build in docker envrionment you can run following cmd directly
docker:
	sudo docker build --force-rm -t k8s-mpam-controller:0.1 .

clean:
	rm -f `go env GOPATH`/bin/agent `go env GOPATH`/bin/server
