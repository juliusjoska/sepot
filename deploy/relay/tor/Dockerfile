# Tor hidden service pro sepot-relay — vlastní minimální image
# (žádný third-party tor image; privacy produkt nemá kam outsourcovat důvěru)
FROM alpine:3.24
RUN apk add --no-cache tor \
    && mkdir -p /var/lib/tor \
    && chown -R tor:tor /var/lib/tor \
    && chmod 700 /var/lib/tor
COPY torrc /etc/tor/torrc
USER tor
CMD ["tor", "-f", "/etc/tor/torrc"]
