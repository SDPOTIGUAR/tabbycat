# Fallback local de emergência — Tabbycat

Sobe o stack completo (db + redis + web + worker + Caddy) neste notebook,
usando as mesmas imagens/config do deploy principal. Só entra em uso se o
Oracle Cloud cair durante um torneio.

## Subir

```bash
cd "TABBY SDP"
TABBYCAT_DOMAIN=viii-interno.sdpotiguar.org \
  podman-compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.fallback.yml up -d
```

`TABBYCAT_DOMAIN` é obrigatório — sem ele o Caddy não sobe (falha rápido,
de propósito). Pra teste local sem domínio real, use `TABBYCAT_DOMAIN=localhost`
(Caddy emite certificado local automaticamente, sem validação externa).

## Derrubar

```bash
podman-compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.fallback.yml down
```

## Portas 80/443 (não é automático)

Rootless podman não binda portas privilegiadas por padrão. O compose hoje
publica Caddy em `8080`/`8443` no host. Pra tráfego real de fora bater em
80/443, duas opções:

1. **Tradução no roteador (recomendado)** — encaminha WAN:443 → IP-do-notebook:8443
   (e WAN:80 → :8080 se quiser redirect automático http→https). Não exige
   mudar nada no sistema, mantém o podman totalmente rootless.
2. **sysctl no host** — `sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80`
   (ou persistir em `/etc/sysctl.conf`) e trocar as portas do compose de volta
   pra `80:80`/`443:443`. Enfraquece o isolamento rootless; só se a opção 1
   não for viável no roteador.

## DNS

Domínio: `viii-interno.sdpotiguar.org` (mesmo link do Oracle) com TTL curto.
Durante a emergência, repontar o registro A pro IP público de casa; depois,
repontar de volta pro Oracle.

## Checklist de hardening antes de ativar

- [ ] Firewalld: só libera a porta usada no port-forward (8443, ou 443 se for
      a opção sysctl). Nunca abrir 22 (SSH) nem a porta interna do Django (8000).
      ```bash
      ! sudo firewall-cmd --add-port=8443/tcp --permanent
      ! sudo firewall-cmd --add-port=8080/tcp --permanent   # só se for usar redirect http
      ! sudo firewall-cmd --reload
      ```
      Pra desativar depois da emergência:
      ```bash
      ! sudo firewall-cmd --remove-port=8443/tcp --permanent
      ! sudo firewall-cmd --remove-port=8080/tcp --permanent
      ! sudo firewall-cmd --reload
      ```
- [ ] Auditar o que mais está escutando no notebook (KDE Connect, Samba,
      CUPS etc.) — nada disso pode ficar alcançável de fora além da porta
      forwardada.
- [ ] `DEBUG=0` confirmado (já é o padrão do `docker-compose.prod.yml` —
      não mudar isso durante o teste).
- [ ] Backup do Postgres antes de ativar (`podman exec tabbysdp_db_1 pg_dump
      -U tabbycat tabbycat > backup.sql`) e depois de encerrar a emergência.
- [ ] Fedora atualizado (`sudo dnf upgrade`) antes de expor.
- [ ] Janela de exposição curta: só ativa o port-forward no roteador durante
      a emergência de fato; desativa (e reverte o firewalld) assim que o
      Oracle voltar.

## O que falta pra isso funcionar de ponta a ponta

- Cadastro na Oracle Cloud (Always Free) — só o Leo consegue fazer.
- Registro A de `viii-interno.sdpotiguar.org` com TTL curto — a criar no
  provedor de DNS do domínio.
- Config do roteador de casa (port-forward) — a fazer só na hora da
  emergência, não deixar ligado por padrão.
