# Build k8s-mpam-controller
FROM golang:1.20.7 as builder

WORKDIR /go/src/k8s-mpam-controller
COPY . /go/src/k8s-mpam-controller

# use "go get" instead of "go mod" to bypass client-go dependence issue
# use build.sh to bypass error: "The command '/bin/sh -c go get -d -v ./...' returned a non-zero code: 1"
RUN ./build.sh

# Create k8s-mpam-controller image
FROM openeuler-22.03-lts-sp2:latest

COPY --from=builder /go/bin/agent /usr/bin/
