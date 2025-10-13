# Use the oficial image of mkdocs-material
FROM squidfunk/mkdocs-material

# Set build directory
WORKDIR /tmp

# Install extra plugins
RUN \
  apk upgrade --update-cache -a \
&& \
  apk add --no-cache weasyprint gcc g++ python3-dev \
&& \
  pip install --no-cache-dir --upgrade pip \
&& \
  pip install --no-cache-dir mkdocs-to-pdf mkdocs-print-site-plugin htmlark[http,parsers] mkdocs-autorefs \
&& \
  rm -rf /tmp/*

# Set working directory
WORKDIR /docs

# Expose MkDocs development server port
EXPOSE 8000

# Start development server
ENTRYPOINT ["/sbin/tini", "--", "mkdocs"]
CMD ["serve", "--livereload", "--dev-addr=0.0.0.0:8000"]
