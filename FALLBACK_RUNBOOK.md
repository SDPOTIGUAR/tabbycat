# Tabbycat self-hosted — roteiro de operação

## Método ativo agora: Oracle Cloud (VPS real, certificado real)

**URL do torneio: https://sdp-viii-interno.duckdns.org/**

Instância `tabbycat` na Oracle Cloud (Always Free/Free Trial), São Paulo
(`sa-saopaulo-1`), Ubuntu 24.04 ARM64, shape `VM.Standard.A2.Flex` (2 OCPU/12GB
— **não é Always Free**, roda com crédito do Free Trial de propósito, ver
nota de billing abaixo). Docker (não Podman — mais estável nesse Ubuntu).

- **IP público:** `163.176.41.81`
- **SSH:** `ssh -i ~/.ssh/oracle_tabbycat ubuntu@163.176.41.81`
- **Projeto na VM:** `~/tabbycat` (clonado direto do GitHub, branch `develop`)
- **Subir/reiniciar:**
  ```bash
  ssh -i ~/.ssh/oracle_tabbycat ubuntu@163.176.41.81
  cd ~/tabbycat
  sudo docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.oracle.yml up -d
  ```
- **Logs:**
  ```bash
  sudo docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.oracle.yml logs <serviço> --tail 50
  ```
- **HTTPS:** Caddy com certificado real (Let's Encrypt automático, `Caddyfile.oracle`)
  — diferente do notebook, aqui as portas 80/443 não são bloqueadas por
  operadora nenhuma, então não precisou de DNS-01/DuckDNS/deSEC, foi automático.
- **DNS:** `sdp-viii-interno.duckdns.org` aponta pro IP da Oracle (fixo
  enquanto a instância não for recriada — não precisa de updater automático
  rodando, mas não custa nada deixar).

**⚠️ Billing:** o shape `A2.Flex` não é Always Free (só o `A1.Flex` é).
Está rodando de propósito no crédito do Free Trial ($300/30 dias) por
decisão consciente do Leo, depois de esbarrar em "Out of Capacity"
tentando A1. Acompanhar o billing da conta Oracle antes do crédito
acabar — depois disso, ou migra pra A1.Flex (grátis, exige recriar a
instância) ou passa a ser cobrado.

**Credenciais/config guardadas:**
- Chave SSH: `~/.ssh/oracle_tabbycat` (privada) / `.pub` (pública)
- Config da OCI CLI: `~/.oci/config` + `~/.oci/oci_api_key.pem`
- Imagem `ocicli` local (Docker/Podman) com o CLI da Oracle instalado,
  pra gerenciar a instância por linha de comando sem precisar da UI web
  (que se mostrou bem confusa de navegar).

## Método anterior (notebook + Cloudflare Tunnel) — desativado, mantido como referência

Antes da Oracle, o stack rodava neste notebook via Podman, exposto por
**Cloudflare Tunnel** (`cloudflared`). Funcionava, mas tinha as limitações
de URL efêmera e não ser 100% self-hosted. Ver seção "Histórico" mais
abaixo pra entender toda a sequência (roteador, Caddy, DNS-01) que levou
até aqui — vale como referência se a Oracle cair e precisar de um
fallback rápido usando o que já está pronto no notebook.

## Referência rápida

Rodar sempre a partir da pasta do projeto:
```bash
cd "~/Desktop/Projetos/TABBY SDP"
```

**Subir tudo:**
```bash
podman-compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.quicktunnel.yml up -d
DUCKDNS_TOKEN=<token de duckdns.org> podman-compose -f docker-compose.duckdns.yml up -d   # opcional, ver nota abaixo
```

**Pegar a URL pública atual** (muda a cada restart do `cloudflared`):
```bash
podman logs tabbysdp_cloudflared_1 2>&1 | grep -A2 "trycloudflare"
```

**Derrubar tudo:**
```bash
podman-compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.quicktunnel.yml -f docker-compose.duckdns.yml down
```

**Ver status de tudo:**
```bash
podman ps -a --filter "name=tabbysdp" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

**Ver logs de um serviço** (`web`, `worker`, `db`, `redis`, `cloudflared`, `duckdns`):
```bash
podman logs tabbysdp_<serviço>_1 --tail 50
podman logs -f tabbysdp_web_1        # acompanhar em tempo real
```

**Reiniciar só um serviço** (sem derrubar o resto):
```bash
podman restart tabbysdp_<serviço>_1
```
**Cuidado com `tabbysdp_cloudflared_1`**: reiniciar troca a URL pública.
Só reiniciar se a URL já não tiver sido divulgada, ou avisando todo mundo
da URL nova depois.

**Testar se está respondendo** (local, de dentro de casa):
```bash
curl -sI http://127.0.0.1:8000/
```
Deve responder `302` apontando pra `/start/` ou pra tela de login.

**Backup do banco:**
```bash
podman exec tabbysdp_db_1 pg_dump -U tabbycat tabbycat > backup-$(date +%Y%m%d-%H%M).sql
```

**Restaurar backup:**
```bash
cat backup-XXXXXXXX.sql | podman exec -i tabbysdp_db_1 psql -U tabbycat tabbycat
```

## Por que Cloudflare Tunnel (não é a opção "mais self-hosted")

Trade-off consciente: Cloudflare Tunnel roteia o tráfego pela rede deles
(não é 100% ponta-a-ponta self-hosted), mas foi o que sobrou funcionando
depois de esgotar as alternativas mais self-hosted numa mesma madrugada
(ver histórico completo abaixo). Sem porta pra abrir, sem depender do
roteador, sem a operadora no meio decidindo se deixa passar.

**Limitação real**: o Quick Tunnel (sem conta Cloudflare) gera uma URL
aleatória que **muda a cada restart do container** — não dá pra usar
pra mandar login por e-mail com antecedência. Isso só se resolve com
Oracle (adiado) ou domínio próprio.

## Histórico — o que foi tentado antes de chegar aqui

Nessa ordem, todos na mesma madrugada:

1. **HTTP puro, IP direto, port-forward no roteador** — funcionou
   inicialmente (confirmado por fora, via 4G). Precisou descobrir na
   prática que a Vivo bloqueia permanentemente as portas "clássicas"
   (80, 443 e outras abaixo de 1024) no nível da operadora — porta
   externa teve que ser >1024 (usamos 8443).
2. **HTTPS com Caddy + certificado autoassinado (`tls internal`)** —
   necessário porque WhatsApp/Chrome forçam `https://` em qualquer link
   automaticamente, e sem TLS nenhum escutando a conexão falha
   (`ERR_SSL_PROTOCOL_ERROR`), não é só aviso. Funcionava no Firefox,
   travava no Chrome.
3. **Diagnóstico do travamento no Chrome** — Caddy anuncia HTTP/3 (QUIC,
   roda sobre UDP); só a porta TCP estava liberada no roteador. Chrome
   tenta QUIC primeiro e, combinado com um bug conhecido do Chrome
   especificamente com QUIC + certificado autoassinado, não faz o
   fallback limpo pra TCP. Corrigido com `servers { protocols h1 h2 }`
   no Caddyfile — confirmado resolvido.
4. **Certificado real via DNS-01 com DuckDNS** — três abordagens
   diferentes (plugin nativo do Caddy, hook manual, plugin dedicado do
   certbot), todas falharam por nameservers do DuckDNS instáveis
   (valor vazio no TXT, SERVFAIL, travamentos) — confirmado que não era
   config nossa, é o provedor.
5. **Certificado real via DNS-01 com deSEC** — chegou mais longe (conta
   ACME real, desafio tentado), mas bateu numa incompatibilidade
   persistente de validação DNSSEC (NSEC3) entre o Let's Encrypt e a
   assinatura do deSEC pra esse domínio especificamente. Confirmado via
   múltiplas tentativas (produção e staging) que não era só demora de
   propagação.
6. **De volta pro autoassinado + fix do Chrome** — funcionando, mas
   depois de um tempo a conexão externa começou a dar **"connection
   refused"** (não mais timeout) mesmo com a configuração do roteador
   conferida duas vezes (regra de redirecionamento + firewall pinhole,
   idênticas e corretas nas duas checagens) e **depois de reiniciar o
   roteador** — o que descarta dessincronia de config. Ver análise
   detalhada logo abaixo.
7. **Cloudflare Tunnel (atual)** — sem porta, sem depender do roteador
   nem da operadora. Funcionando.

### Sobre o "connection refused" súbito (item 6) — o que sabemos e o que não sabemos

**O que é consistente com a evidência:**
- A porta funcionava (testada e confirmada por fora, via 4G, mais de
  uma vez) e parou de funcionar depois de várias horas de testes
  repetidos e intensos na mesma porta/IP.
- ISPs residenciais (Vivo inclusa, por política documentada em termos
  de uso similares — ex. Comcast) têm sistemas automatizados de
  detecção de abuso que podem bloquear tráfego que se pareça com scan
  de porta ou uso "tipo servidor" incomum numa linha residencial.
- A configuração do roteador (regra de porta + firewall pinhole) foi
  conferida duas vezes, idêntica e correta, e **sobreviveu a um reboot
  do roteador** — descarta bug de sincronização de UI vs. config real
  aplicada.

**O que não foi possível confirmar (limitação real do diagnóstico):**
- O teste de "connection refused" foi feito por mim via uma ferramenta
  de fetch que roda de infraestrutura de nuvem (não um celular real).
  Provedores costumam tratar faixas de IP conhecidas de datacenter/nuvem
  com mais suspeita do que tráfego de operadora móvel — é possível que
  o bloqueio seja especificamente contra esse tipo de origem, e que um
  celular real (numa rede móvel comum) tivesse um resultado diferente.
  Isso **não foi testado novamente a partir do celular depois do reboot**
  antes de decidirmos migrar pro Cloudflare Tunnel — journal em aberto,
  não fechado com certeza absoluta.
- Não há confirmação oficial da Vivo (documentação pública ou suporte)
  de um sistema automático de bloqueio por tráfego anômalo — a hipótese
  é razoável e consistente com práticas comuns de ISP, mas não
  encontrada documentada especificamente pra Vivo.

**Conclusão prática:** mesmo que a causa exata do "connection refused"
fique em aberto, o padrão da noite (bloqueio de portas conhecidas +
esse novo bloqueio pouco claro) reforça que depender dessa conexão
residencial pra hospedar algo publicamente é frágil. Cloudflare Tunnel
contorna o problema inteiro (conexão sempre de saída, nunca precisa de
porta aberta).

## Roteador (Vivo Box / Inventus RTF8225VW) — referência, não está em uso agora

Painel em `192.168.15.1`, login `admin` + senha na etiqueta do aparelho.
Menu: **Configurações → Rede Local → Redirecionar Portas**. Regra que
tínhamos configurado (não removida, só não está mais no caminho ativo):
TCP, externa `8443`, interna `8443`, IP interno `192.168.15.7`.

## URL fixa (DuckDNS) — ainda relevante como updater de IP

O container `docker-compose.duckdns.yml` mantém `sdp-viii-interno.duckdns.org`
apontando pro IP público atual desta conexão. Não é mais usado como parte
do caminho de acesso principal (isso agora é a URL do Cloudflare Tunnel),
mas não custa deixar rodando — pode ser útil se algum dia reativarmos o
caminho via roteador.

## Checklist de hardening (relevante se algum dia voltar a expor porta direta)

- [ ] Firewalld local: confirmar que a porta usada está liberada.
      ```bash
      ! sudo firewall-cmd --add-port=8000/tcp --permanent
      ! sudo firewall-cmd --reload
      ```
- [ ] Auditar o que mais está escutando no notebook (KDE Connect, Samba,
      CUPS etc.).
- [ ] `DEBUG=0` confirmado (já é o padrão do `docker-compose.prod.yml`).
- [ ] Backup do Postgres antes do evento e depois de encerrar.
- [ ] Fedora atualizado (`sudo dnf upgrade`) antes de expor por longos períodos.

Com Cloudflare Tunnel, a única porta relevante é a **de saída** (o
container conecta nele mesmo, não precisa liberar nada de entrada) —
esse checklist deixa de ser crítico enquanto o Tunnel for o método ativo.

## Status

- Cadastro na Oracle Cloud (Always Free) — feito, **reservado como
  último recurso**, só usar se as opções self-hosted se esgotarem de
  vez (decisão explícita do Leo).
- Cloudflare Tunnel — ativo agora, funcionando, URL efêmera.
- Caddy + autoassinado + roteador — configurado e documentado, mas fora
  do caminho ativo (bloqueio do lado da operadora).
- Certificado real via DNS-01 (DuckDNS e deSEC) — abandonado por
  motivos do lado dos provedores. Plugins de ambos continuam compilados
  na imagem do Caddy (`Dockerfile.caddy`) caso valha retomar.
- Falta resolver: URL estável (pra mandar login por e-mail com
  antecedência) — Quick Tunnel não serve pra isso. Precisa de conta
  Cloudflare + domínio próprio, ou Oracle, quando chegar a hora.
