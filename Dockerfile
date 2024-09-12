FROM alpine:3.18
RUN apk --no-cache add gettext postgresql-client bash
RUN apk add --no-cache coreutils

RUN adduser --disabled-password --shell=/bin/bash user

USER root
RUN mkdir /work
WORKDIR /work

COPY scripts/*.tmpl /work/
COPY scripts/*.sh /work/
RUN chmod +x /work/*.sh

USER user

ENTRYPOINT ["bash","/work/init.sh"]
