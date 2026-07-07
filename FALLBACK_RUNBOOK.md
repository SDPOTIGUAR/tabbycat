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

**Credenciais/config guardadas** (valores reais só na máquina local / Bitwarden,
nunca neste arquivo — o repo vive no GitHub, potencialmente público):

| O quê | Onde vive | Pra que serve |
|---|---|---|
| Conta Oracle Cloud | login `leonardoalcantara427@gmail.com` (Bitwarden) | conta da nuvem, região São Paulo |
| Chave SSH da instância | `~/.ssh/oracle_tabbycat` (priv.) / `.pub` neste notebook, perms 600 | acesso `ssh ubuntu@<ip>` na VM |
| OCI API key (usuário IAM) | `~/.oci/config` + `~/.oci/oci_api_key.pem`, perms 600 | autentica o `oci` CLI (via imagem `ocicli`) pra gerenciar a instância sem depender da UI web (que se mostrou confusa) |
| Conta DuckDNS | domínio `sdp-viii-interno.duckdns.org` | hostname fixo, token de update guardado só como env var na hora de rodar, nunca em arquivo |
| Conta deSEC (abandonada) | domínio `sdpotiguar.dedyn.io` | tentativa de DNS-01 que não funcionou (ver histórico); token não usado mais, mas a conta/domínio continuam existindo caso valha retomar |
| Superusuário do Tabbycat | usuário `ORGANIZAÇÃO` | login do painel admin do torneio; senha só no Bitwarden |
| Senha do Postgres | `tabbycat` (literal, hardcoded no `docker-compose.yml`) | é só um placeholder de dev já público no próprio repositório oficial do Tabbycat, não protege nada sensível sozinha (o banco nem fica exposto de fora) |

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

## Roteador (Vivo Box / Inventus RTF8225VW) — não está mais em uso, tem ponta solta

Painel em `192.168.15.1`, login `admin` + senha na etiqueta do aparelho.
Regra de redirecionamento (`Configurações → Rede Local → Redirecionar
Portas`) e o firewall pinhole correspondente **ainda existem lá**, apontando
pra porta 8443 deste notebook (`192.168.15.7`) — não removidos. Como o
caminho ativo agora é a Oracle, isso não protege nem serve mais pra nada,
é só uma porta aberta sem função. **Recomendo remover essa regra e o
pinhole correspondente** da próxima vez que mexer no roteador, mesmo que
o "connection refused" sugira que pode já não estar passando tráfego —
não custa fechar o que não se usa mais.

## Tabela comparativa — todas as estratégias tentadas

| Método | Resultado | Self-hosted? | Prós | Contras |
|---|---|---|---|---|
| Render (PaaS gratuito) | No ar, mas com worker cortado | Não | Zero manutenção de infra | Free tier (512MB) não cabe web+worker juntos; sem alocação automática |
| HTTP puro + port-forward (Vivo) | Funcionou, depois parou | Sim | Simples, sem terceiro | Vivo bloqueia portas clássicas; "connection refused" sem causa 100% confirmada |
| Caddy autoassinado + roteador | Funcionou (Firefox), trava no Chrome até o fix de HTTP/3 | Sim | Resolve o erro do WhatsApp | Aviso de certificado; depende da rede residencial |
| DNS-01 (DuckDNS / deSEC) | Falhou nos dois | Sim | Certificado real, sem aviso | Nameservers/DNSSEC dos provedores grátis, fora do nosso controle |
| Cloudflare Tunnel | Funcionou | Parcial (roteia pela rede deles) | Sem porta, sem depender de roteador/operadora | URL efêmera (Quick Tunnel), não serve pra e-mail com antecedência |
| **Oracle Cloud (atual)** | **Funcionando, certificado real automático** | Sim (VPS próprio) | URL estável, sem bloqueio de porta, worker completo funcionando | Não é "Always Free" nesse shape (crédito de trial); exige manutenção de VM |

## Checklist de hardening

- [ ] Firewalld local (notebook): sem porta de entrada aberta pro Tabbycat
      é necessário agora (Oracle não depende do notebook pra nada). Se
      algum dia voltar a expor daqui, liberar só a porta específica usada.
- [ ] Auditar o que mais está escutando no notebook (KDE Connect, Samba,
      CUPS etc.) antes de expor qualquer porta de novo.
- [ ] `DEBUG=0` confirmado (já é o padrão do `docker-compose.prod.yml`).
- [ ] Backup do Postgres antes do evento e depois de encerrar (feito —
      ver `backups/`, fora do controle de versão).
- [ ] Fedora atualizado (`sudo dnf upgrade`) se este notebook voltar a
      expor qualquer porta.
- [ ] Remover a regra de port-forward + pinhole no Vivo Box (ver seção
      acima) — ponta solta conhecida, ainda não fechada.

## Auditoria de segurança/limpeza (pós-torneio, 2026-07-07)

Feita depois de desligar tudo e o notebook crashar por sobrecarga de
memória (provavelmente builds/containers em paralelo — anotado, evitar
repetir). O que foi checado:

- **Containers do Tabbycat neste notebook**: removidos (`podman rm -f`),
  só as imagens ficaram (`tabbysdp_web`, `tabbysdp_worker`,
  `tabbysdp_caddy`, `ocicli`, além das bases `caddy`, `cloudflared`,
  `duckdns` puxadas do Docker Hub). Volumes de dados locais (Postgres,
  Redis, Caddy) também removidos — não são mais a fonte de verdade
  (essa passou a ser a Oracle, já com backup).
- **⚠️ Engano meu durante a limpeza**: rodei `podman network prune -f`
  sem escopar só pro Tabbycat, e isso apagou redes órfãs de **outros
  projetos seus** (`main_firefly_iii`, `docker_default`). Confirmei que
  não havia containers rodando usando essas redes no momento — o Podman
  Compose recria a rede automaticamente na próxima vez que esses
  projetos subirem, então não deve ter causado perda de dados, mas foi
  uma ação mais ampla do que devia.
- **Firewalld local (notebook)**: achei uma regra ampla e permanente já
  ativa — `ports: 1025-65535/udp 1025-65535/tcp` na zona
  `FedoraWorkstation` (interface Wi-Fi). Isso libera **todas as portas
  não-privilegiadas** de entrada, bem mais do que qualquer coisa que
  pedimos abrir nesta sessão especificamente. Não sei confirmar se já
  existia antes desse projeto ou se foi introduzida em algum momento
  aqui — vale você decidir se quer restringir isso, já que não é
  necessário pra nada relacionado ao Tabbycat agora.
- **Roteador Vivo Box**: regra de port-forward + pinhole pra porta 8443
  continuam configuradas, sem função (ver seção acima) — não removidas
  (sem acesso remoto ao roteador).
- **Oracle Cloud**: instância **parada** (sem cobrança de computação
  enquanto parada). Security list da VCN continua permitindo entrada
  22/80/443 de qualquer origem — sem risco imediato com a instância
  parada, mas vale saber que volta a valer assim que ligar de novo.
- **Credenciais neste notebook**: `~/.ssh/oracle_tabbycat` e
  `~/.oci/oci_api_key.pem`/`config`, todos com permissão `600` (só o
  seu usuário lê). Nenhum token/senha real foi commitado no repositório
  em nenhum momento (sempre passados como variável de ambiente na hora
  de rodar, nunca salvos em arquivo versionado).
- **Skill `/healthcheck`**: atualizada (ver `.claude/commands/healthcheck.md`)
  pra refletir que o método ativo agora é Oracle, atualmente parado.
- **Pods/containers de outros projetos**: `thought-*` (Nextcloud/Purple)
  e `couchdb` seguem intactos, não foram tocados em nenhum momento desta
  sessão.

## Status final

- **Oracle Cloud** — método ativo, instância **parada** pra poupar
  recursos/crédito. Subir de novo com o comando em "Subir/reiniciar" no
  topo deste arquivo.
- **Backup do banco + mídia** — feito, em `backups/` (fora do git).
- **Cloudflare Tunnel / Caddy local / DuckDNS updater no notebook** —
  todos parados/removidos, mantidos só como referência documentada.
- **Ponta solta conhecida, não fechada**: regra de port-forward no
  roteador Vivo (sem função, sem acesso remoto pra remover) e a regra
  ampla de firewalld local (`1025-65535`) — ambas pendentes de decisão
  sua.
- **Alocação automática de juízes/salas** — confirmada funcionando na
  Oracle (worker completo, sem corte de memória como no Render).
