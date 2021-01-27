FROM alpine:3.12
RUN apk --no-cache add gettext postgresql-client bash

RUN adduser --disabled-password --shell=/bin/bash user

USER root
RUN mkdir /work
WORKDIR /work

COPY scripts/*.tmpl /work/
COPY scripts/*.sh /work/
RUN chmod +x /work/*.sh

USER user

ENTRYPOINT ["sh","/work/init.sh"]
