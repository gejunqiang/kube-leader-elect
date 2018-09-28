FROM alpine:3.7

RUN apk add --no-cache bash coreutils curl openssh-client openssl git findutils && \
	curl -sSL "http://npc.nos-eastchina1.126.net/dl/dumb-init_1.2.0_amd64.tar.gz" | tar -zx -C /usr/local/bin && \
	curl -sSL 'http://npc.nos-eastchina1.126.net/dl/jq_1.5_linux_amd64.tar.gz' | tar -zx -C /usr/local/bin && \
	curl -sSL 'https://npc.nos-eastchina1.126.net/dl/kubernetes-client-v1.9.3-linux-amd64.tar.gz' | tar -zx -C /usr/local && \
	ln -s /usr/local/kubernetes/client/bin/kubectl /usr/local/bin/kubectl

ADD kube-leader-elect.sh /usr/local/kube-leader-elect.sh
RUN chmod 755 /usr/local/kube-leader-elect.sh && ln -s /usr/local/kube-leader-elect.sh /usr/local/bin/kube-leader-elect

ENV LEADER_LIFETIME=${LEADER_LIFETIME:-240} \
    LEADER_RENEW="${LEADER_RENEW:-60}" \
    LEADER_HOLDER="${LEADER_HOLDER:-configmap/leader-election}" \
    MEMBER="${MEMBER:-$HOSTNAME}"

ENTRYPOINT [ "/usr/local/bin/dumb-init", "kube-leader-elect"]