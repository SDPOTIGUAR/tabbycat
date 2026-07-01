# Tabbycat self-hosted — roteiro de operação

Stack completo (db + redis + web + worker + atualizador DuckDNS) rodando
neste notebook via Podman. HTTP puro, sem TLS (ver justificativa mais abaixo).

**URL para divulgar:** http://sdp-viii-interno.duckdns.org:8443/

## Referência rápida

Rodar sempre a partir da pasta do projeto:
```bash
cd "~/Desktop/Projetos/TABBY SDP"
```

**Subir tudo:**
```bash
podman-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
DUCKDNS_TOKEN=<token de duckdns.org> podman-compose -f docker-compose.duckdns.yml up -d
```

**Derrubar tudo:**
```bash
podman-compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.duckdns.yml down
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
curl -sI http://127.0.0.1:8000/
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

## Por que HTTP puro, sem TLS/certificado

Decisão deliberada: sem domínio próprio controlável e com a Vivo bloqueando
as portas 80/443 de entrada (única forma de validar certificado real via
Let's Encrypt), não dá pra ter certificado confiável aqui. Certificado
autoassinado só gera aviso assustador pros participantes sem ganho real de
segurança pro contexto (torneio interno, baixo risco). Login/senha trafegam
sem criptografia — aceito conscientemente.

## Roteador (Vivo Box / Inventus RTF8225VW)

Painel em `192.168.15.1`, login `admin` + senha na etiqueta do aparelho.
Menu: **Configurações → Rede Local → Redirecionar Portas**.

| Campo | Valor |
|---|---|
| Nome da Regra | `tabbycat-http` |
| Protocolo | TCP |
| Porta Externa | `8443` |
| Porta Interna | `8000` |
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
- Redirecionamento de porta no roteador — feito e testado (4G externo, confirmado).
- Hostname fixo via DuckDNS — feito e testado (`sdp-viii-interno.duckdns.org`).
- Stack local (db+redis+web+worker) — testado de ponta a ponta, funcionando.
