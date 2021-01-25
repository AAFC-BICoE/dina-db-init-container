FROM alpine:3.12
RUN apk --no-cache add gettext postgresql-client

RUN adduser --disabled-password --shell=/bin/sh user

RUN mkdir /work
WORKDIR /work
USER user
COPY scripts/*.tmpl /work/
COPY scripts/*.sh /work/

ENTRYPOINT ["sh","/work/init.sh"]

