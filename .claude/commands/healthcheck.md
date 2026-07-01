Healthcheck e recuperação automática do stack self-hosted do Tabbycat (torneio VIII Interno SDP), rodando via Podman neste notebook. Ver `FALLBACK_RUNBOOK.md` na raiz do projeto pra contexto completo (roteador, DuckDNS, por que é HTTP puro).

## Quando invocar automaticamente

Triggers: "healthcheck do tabbycat", "verifica se o site está no ar", "o tabbycat caiu", "sobe o tabbycat de novo", "site do torneio fora do ar", ou qualquer menção a checar/restaurar o serviço do torneio.

## Procedimento

### 1. Checar containers
```bash
podman ps -a --filter "name=tabbysdp" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```
Esperado: `tabbysdp_db_1`, `tabbysdp_redis_1`, `tabbysdp_web_1`, `tabbysdp_worker_1`, `tabbysdp_duckdns_1` todos com status `Up`.

### 2. Testar resposta HTTP local
```bash
curl -sI -m 5 http://127.0.0.1:8000/
```
Esperado: `302` redirecionando pra `/start/` ou pra login. Isso confirma que web+db+redis estão realmente respondendo, não só "rodando".

**Não testar via `sdp-viii-interno.duckdns.org:8443` a partir desta máquina** — o roteador não suporta hairpin NAT, essa checagem trava mesmo com tudo saudável. É um falso negativo conhecido, não indica problema.

### 3. Checar o DuckDNS atualizou recentemente
```bash
podman logs tabbysdp_duckdns_1 --tail 5
```
Esperado: linha recente tipo "DuckDNS request ... successful". Se o container estiver down, o hostname para de atualizar silenciosamente (sem erro visível até o IP mudar de verdade).

### 4. Se algo estiver down ou não responder

Reiniciar só o que precisa, na ordem de dependência (db/redis primeiro, depois web/worker, duckdns é independente):
```bash
podman restart tabbysdp_db_1 tabbysdp_redis_1
sleep 5
podman restart tabbysdp_web_1 tabbysdp_worker_1
podman restart tabbysdp_duckdns_1
```

Se um container não existir mais (foi removido, não só parado), subir tudo de novo:
```bash
cd "TABBY SDP"
podman-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```
(o DuckDNS precisa do token, que não fica salvo em nenhum arquivo — se o container `tabbysdp_duckdns_1` sumiu de vez, avisar o Leo que precisa do `DUCKDNS_TOKEN` de novo pra recriar, não tentar adivinhar ou usar um valor antigo do histórico do bash.)

### 5. Re-testar depois de qualquer restart
Repetir o passo 2 (`curl` local). Se ainda falhar depois do restart, checar logs do serviço específico (`podman logs tabbysdp_web_1 --tail 50`) e reportar o erro real ao Leo em vez de tentar mais reinícios às cegas.

### 6. Reportar

Resumo direto: o que estava down (se algo estava), o que foi feito, e o resultado do teste final. Se estiver tudo certo desde o início, só confirmar em uma linha — não narrar o processo inteiro.

## Fora do escopo desta skill

- Configuração do roteador (redirecionamento de porta, IP interno) — isso é manual, no painel `192.168.15.1`, documentado no `FALLBACK_RUNBOOK.md`.
- Mudança de porta externa, domínio ou infraestrutura — isso é decisão do Leo, não uma correção automática.
- Rodar `sudo` (firewalld etc.) — sempre pedir pro Leo rodar via `!`, nunca tentar contornar.
