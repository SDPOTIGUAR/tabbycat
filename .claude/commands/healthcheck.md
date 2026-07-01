Healthcheck e recuperação automática do stack self-hosted do Tabbycat (torneio VIII Interno SDP), rodando via Podman neste notebook, exposto via Cloudflare Tunnel. Ver `FALLBACK_RUNBOOK.md` na raiz do projeto pra contexto completo e histórico (por que Cloudflare Tunnel, não roteador/Caddy).

## Quando invocar automaticamente

Triggers: "healthcheck do tabbycat", "verifica se o site está no ar", "o tabbycat caiu", "sobe o tabbycat de novo", "site do torneio fora do ar", ou qualquer menção a checar/restaurar o serviço do torneio.

## Procedimento

### 1. Checar containers
```bash
podman ps -a --filter "name=tabbysdp" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```
Esperado: `tabbysdp_db_1`, `tabbysdp_redis_1`, `tabbysdp_web_1`, `tabbysdp_worker_1`, `tabbysdp_cloudflared_1` todos com status `Up`. `tabbysdp_duckdns_1` também, se estiver rodando (não crítico pro acesso atual).

### 2. Testar resposta HTTP local
```bash
curl -sI -m 5 http://127.0.0.1:8000/
```
Esperado: `302` redirecionando pra `/start/` ou pra login. Isso confirma que web+db+redis estão realmente respondendo, não só "rodando".

### 3. Confirmar a URL pública do Cloudflare Tunnel e testar de fato
```bash
podman logs tabbysdp_cloudflared_1 2>&1 | grep -A2 "trycloudflare"
curl -sI -m 8 <url encontrada>
```
Essa URL muda toda vez que o container `cloudflared` reinicia — se o Leo perguntar "qual é o link", sempre pegar do log agora, nunca reusar um link antigo sem checar.

### 4. Se algo estiver down ou não responder

Reiniciar só o que precisa, na ordem de dependência (db/redis primeiro, depois web/worker; cloudflared por último e só se necessário, já que reiniciar ele troca a URL pública):
```bash
podman restart tabbysdp_db_1 tabbysdp_redis_1
sleep 5
podman restart tabbysdp_web_1 tabbysdp_worker_1
```
Só reiniciar `tabbysdp_cloudflared_1` se ele próprio estiver down — e avisar o Leo que a URL pública vai mudar.

Se um container não existir mais (foi removido, não só parado), subir tudo de novo:
```bash
cd "TABBY SDP"
podman-compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.quicktunnel.yml up -d
```

### 5. Re-testar depois de qualquer restart
Repetir o passo 2 (`curl` local). Se ainda falhar depois do restart, checar logs do serviço específico (`podman logs tabbysdp_web_1 --tail 50`) e reportar o erro real ao Leo em vez de tentar mais reinícios às cegas.

### 6. Reportar

Resumo direto: o que estava down (se algo estava), o que foi feito, e o resultado do teste final. Se estiver tudo certo desde o início, só confirmar em uma linha — não narrar o processo inteiro.

## Fora do escopo desta skill

- Configuração do roteador (redirecionamento de porta, IP interno) — isso é manual, no painel `192.168.15.1`, documentado no `FALLBACK_RUNBOOK.md`.
- Mudança de porta externa, domínio ou infraestrutura — isso é decisão do Leo, não uma correção automática.
- Rodar `sudo` (firewalld etc.) — sempre pedir pro Leo rodar via `!`, nunca tentar contornar.
