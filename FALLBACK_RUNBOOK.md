# Tabbycat self-hosted — roteiro de operação

Stack completo (db + redis + web + worker + Caddy + atualizador DuckDNS)
rodando neste notebook via Podman. HTTPS com certificado autoassinado (ver
justificativa mais abaixo).

**URL para divulgar:** https://sdp-viii-interno.duckdns.org:8443/
(vai pedir pra aceitar o aviso de certificado — normal, é autoassinado)

## Referência rápida

Rodar sempre a partir da pasta do projeto:
```bash
cd "~/Desktop/Projetos/TABBY SDP"
```

**Subir tudo:**
```bash
TABBYCAT_DOMAIN=sdp-viii-interno.duckdns.org \
  podman-compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.fallback.yml up -d
DUCKDNS_TOKEN=<token de duckdns.org> podman-compose -f docker-compose.duckdns.yml up -d
```

**Derrubar tudo:**
```bash
podman-compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.fallback.yml -f docker-compose.duckdns.yml down
```

**Ver status de tudo:**
```bash
podman ps -a --filter "name=tabbysdp" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

**Ver logs de um serviço** (`web`, `worker`, `db`, `redis`, `duckdns`):
```bash
podman logs tabbysdp_<serviço>_1 --tail 50
podman logs -f tabbysdp_web_1        # acompanhar em tempo real
```

**Reiniciar só um serviço** (sem derrubar o resto):
```bash
podman restart tabbysdp_<serviço>_1
```

**Testar se está respondendo** (local, de dentro de casa):
```bash
curl -sI http://127.0.0.1:8000/           # web direto, sem TLS
curl -sk -o /dev/null -w '%{http_code}\n' https://127.0.0.1:8443/   # via Caddy
```
Deve responder `302` apontando pra `/start/` ou pra tela de login. Testar
pelo hostname público (`sdp-viii-interno.duckdns.org:8443`) **de dentro de
casa trava sempre** — o roteador não suporta hairpin NAT. Isso não indica
problema real; só o teste por fora (celular no 4G/5G, Wi-Fi desligado) é
confiável.

**Backup do banco:**
```bash
podman exec tabbysdp_db_1 pg_dump -U tabbycat tabbycat > backup-$(date +%Y%m%d-%H%M).sql
```

**Restaurar backup:**
```bash
cat backup-XXXXXXXX.sql | podman exec -i tabbysdp_db_1 psql -U tabbycat tabbycat
```

## Por que HTTPS autoassinado (não certificado real)

Sem domínio próprio controlável e com a Vivo bloqueando as portas 80/443 de
entrada (a forma padrão de validar certificado real via Let's Encrypt), não
dá pra ter certificado confiável direto. Tentamos contornar isso via DNS-01
usando o DuckDNS (que não depende de porta nenhuma pra validar) — três
abordagens diferentes, todas esbarraram nos nameservers do próprio DuckDNS
estando instáveis (SERVFAIL, timeout). Não é bloqueado pra sempre — pode
valer tentar de novo depois, mas não é algo pra depender agora.

Por que HTTPS mesmo assim (em vez de manter HTTP puro): WhatsApp e navegadores
modernos forçam `https://` automaticamente em qualquer link, mesmo quando
compartilhado com `http://` explícito — sem TLS nenhum escutando na porta, a
conexão falha (`ERR_SSL_PROTOCOL_ERROR`), não é só um aviso, é erro total.
Certificado autoassinado troca essa falha total por um aviso clicável
("não seguro", um clique resolve) — não é bonito, mas funciona.

**Chrome travava (Firefox não) com o autoassinado — causa achada e corrigida:**
o roteador só libera TCP na porta 8443 (UDP não é redirecionado). O Caddy
anuncia HTTP/3 (QUIC, que roda sobre UDP) por padrão; o Chrome tenta QUIC
primeiro e, combinado com um bug/comportamento conhecido do Chrome
especificamente com QUIC + certificado autoassinado, não faz o fallback
limpo pra TCP — trava até dar timeout. O Firefox não tenta QUIC do mesmo
jeito num domínio novo, por isso funcionava direto nele. Corrigido forçando
`servers { protocols h1 h2 }` no Caddyfile (desabilita HTTP/3 de vez).
Ainda precisa de confirmação externa no Chrome pra fechar de vez.

## Roteador (Vivo Box / Inventus RTF8225VW)

Painel em `192.168.15.1`, login `admin` + senha na etiqueta do aparelho.
Menu: **Configurações → Rede Local → Redirecionar Portas**.

| Campo | Valor |
|---|---|
| Nome da Regra | `tabbycat-http` |
| Protocolo | TCP |
| Porta Externa | `8443` |
| Porta Interna | `8443` (aponta pro Caddy, não mais direto pro web/8000) |
| IP Interno | `192.168.15.7` (IP local deste notebook — conferir se mudou) |

**Por que porta externa 8443 e não 80:** a Vivo bloqueia permanentemente as
portas de entrada "clássicas" (80, 443, 21, 23, 25, 53 e demais abaixo de
1024) no nível da própria operadora pra planos residenciais — nenhuma
configuração de roteador contorna isso, só existe desbloqueio em link
dedicado/empresarial. Portas acima de 1024 passam livremente.

O painel gera automaticamente uma regra de firewall ("pinhole") junto com o
redirecionamento — não precisa mexer na aba Firewall separadamente.

Se o notebook trocar de IP local (reconecta no Wi-Fi, reinicia etc.),
conferir com `ip route get 8.8.8.8` e atualizar o IP Interno da regra.

## URL fixa (DuckDNS)

O IP público é dinâmico — pra endereço estável o suficiente pra mandar
login por e-mail com antecedência, o `docker-compose.duckdns.yml` sobe um
container que mantém `sdp-viii-interno.duckdns.org` sempre apontando pro IP
atual desta conexão, checando a cada poucos minutos. Esse container precisa
continuar rodando desde antes de mandar os e-mails de login, não só no dia
do evento.

## Checklist de hardening antes de ativar de verdade

- [ ] Firewalld local: confirmar que a porta 8000 está liberada.
      ```bash
      ! sudo firewall-cmd --add-port=8000/tcp --permanent
      ! sudo firewall-cmd --reload
      ```
      Pra desativar depois:
      ```bash
      ! sudo firewall-cmd --remove-port=8000/tcp --permanent
      ! sudo firewall-cmd --reload
      ```
- [ ] Auditar o que mais está escutando no notebook (KDE Connect, Samba,
      CUPS etc.) — nada disso pode ficar alcançável de fora além da porta
      forwardada.
- [ ] `DEBUG=0` confirmado (já é o padrão do `docker-compose.prod.yml` —
      não mudar isso).
- [ ] Backup do Postgres antes do evento e depois de encerrar.
- [ ] Fedora atualizado (`sudo dnf upgrade`) antes de expor por longos períodos.

## Status

- Cadastro na Oracle Cloud (Always Free) — feito, uso adiado pra depois.
- Redirecionamento de porta no roteador — feito, mas precisa apontar pra
  8443 (Caddy) em vez de 8000 (web) depois da mudança pra HTTPS.
- Hostname fixo via DuckDNS — feito e testado (`sdp-viii-interno.duckdns.org`).
- Stack local (db+redis+web+worker+caddy) — testado de ponta a ponta com
  certificado autoassinado, funcionando.
- Certificado real via DNS-01 — tentado com DuckDNS (nameservers instáveis)
  e deSEC (incompatibilidade de validação DNSSEC), ambos abandonados por
  motivos do lado dos provedores, não da nossa config. Plugins de ambos
  continuam compilados na imagem do Caddy caso valha retomar depois.
- Chrome travando no autoassinado — diagnosticado como QUIC/HTTP3 tentando
  UDP (porta não liberada) + bug conhecido do Chrome nessa combinação com
  certificado autoassinado. Corrigido desabilitando HTTP/3 no Caddy. Falta
  confirmação externa no Chrome.
