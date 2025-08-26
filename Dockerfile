ARG GOLANG_VERSION=1.25.0
FROM golang:${GOLANG_VERSION}-trixie AS builder

ARG IMAGINARY_VERSION=production
ARG GOLANGCILINT_VERSION=2.4.0

# Installs libvips + required libraries
RUN DEBIAN_FRONTEND=noninteractive \
  apt-get update && \
  apt-get install --no-install-recommends -y \
  ca-certificates \
  automake build-essential curl \
  gobject-introspection gtk-doc-tools libglib2.0-dev libjpeg62-turbo-dev libpng-dev \
  libwebp-dev libtiff5-dev libgif-dev libexif-dev libxml2-dev libpoppler-glib-dev \
  swig libmagickwand-dev libpango1.0-dev libmatio-dev libopenslide-dev libcfitsio-dev \
  libgsf-1-dev libfftw3-dev liborc-0.4-dev librsvg2-dev libimagequant-dev libheif-dev \
  libvips-dev libvips-tools libvips42t64

# Installing golangci-lint
WORKDIR /tmp
RUN curl -fsSL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b "${GOPATH}/bin" v${GOLANGCILINT_VERSION}

WORKDIR ${GOPATH}/src/github.com/panperla/imaginary

COPY go.mod .
COPY go.sum .

RUN go mod download
RUN go mod verify
# Copy imaginary sources
COPY . .

# Run quality control
RUN go test ./... -test.v -race -test.coverprofile=atomic .
RUN golangci-lint run .

# Compile imaginary
RUN go build -a \
    -o ${GOPATH}/bin/imaginary \
    -ldflags="-s -w -h -X main.Version=${IMAGINARY_VERSION}" \
    github.com/panperla/imaginary

FROM debian:trixie-slim

ARG IMAGINARY_VERSION

LABEL maintainer="tomas@aparicio.me" \
      org.label-schema.description="Fast, simple, scalable HTTP microservice for high-level image processing with first-class Docker support" \
      org.label-schema.schema-version="1.0" \
      org.label-schema.url="https://github.com/h2non/imaginary" \
      org.label-schema.vcs-url="https://github.com/h2non/imaginary" \
      org.label-schema.version="${IMAGINARY_VERSION}"

COPY --from=builder /usr/local/lib /usr/local/lib
COPY --from=builder /go/bin/imaginary /usr/local/bin/imaginary
COPY --from=builder /etc/ssl/certs /etc/ssl/certs

# Install runtime dependencies
RUN DEBIAN_FRONTEND=noninteractive \
  apt-get update && \
  apt-get install --no-install-recommends -y \
  procps libglib2.0-0 libjpeg62-turbo libpng16-16 libopenexr-3-1-30  \
  libwebp7 libwebpmux3 libwebpdemux2 libtiff6 libgif7 libexif12 libxml2 libpoppler-glib8 \
  libmagickwand-7.q16-10 libpango-1.0-0 libmatio13 libopenslide0 libjemalloc2 \
  libgsf-1-114 libfftw3-bin libfftw3-dev liborc-0.4-0 librsvg2-2 libcfitsio10t64 libimagequant0 libheif1 libvips42t64 && \
  ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
  apt-get autoremove -y && \
  apt-get autoclean && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so

# Server port to listen
ENV PORT=9000

# Drop privileges for non-UID mapped environments
USER nobody

# Run the entrypoint command by default when the container starts.
ENTRYPOINT ["/usr/local/bin/imaginary"]

# Expose the server TCP port
EXPOSE ${PORT}
