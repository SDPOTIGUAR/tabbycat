Healthcheck e recuperação automática do Tabbycat (torneio VIII Interno SDP). Rodando primariamente na **Oracle Cloud** (VM `tabbycat`, São Paulo, IP `163.176.41.81`, Docker). O notebook local (Podman + Cloudflare Tunnel) é fallback, não o método ativo. Ver `FALLBACK_RUNBOOK.md` na raiz do projeto pra contexto completo e histórico.

## Quando invocar automaticamente

Triggers: "healthcheck do tabbycat", "verifica se o site está no ar", "o tabbycat caiu", "sobe o tabbycat de novo", "site do torneio fora do ar", ou qualquer menção a checar/restaurar o serviço do torneio.

## Procedimento (Oracle — método ativo)

### 1. Checar containers na VM
```bash
ssh -i ~/.ssh/oracle_tabbycat ubuntu@163.176.41.81 "cd ~/tabbycat && sudo docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.oracle.yml ps"
```
Esperado: `db`, `redis`, `web`, `worker`, `caddy` todos `Up`/`running`.

### 2. Testar a URL pública de verdade
```bash
curl -sI -m 8 https://sdp-viii-interno.duckdns.org/
```
Esperado: `302` pra `/start/` ou login, certificado real (sem precisar de `-k`). Diferente do notebook, aqui **não tem falso negativo de hairpin NAT** — se esse curl falhar rodando local, é problema de verdade.

### 3. Se algo estiver down

```bash
ssh -i ~/.ssh/oracle_tabbycat ubuntu@163.176.41.81
cd ~/tabbycat
sudo docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.oracle.yml up -d
```
Isso recria/reinicia só o que precisar, sem derrubar o resto.

### 4. Logs de um serviço específico
```bash
ssh -i ~/.ssh/oracle_tabbycat ubuntu@163.176.41.81 "cd ~/tabbycat && sudo docker compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.oracle.yml logs <serviço> --tail 50"
```

### 5. Re-testar depois de qualquer ação
Repetir o passo 2. Se ainda falhar, checar logs do serviço específico e reportar o erro real ao Leo em vez de tentar mais reinícios às cegas.

## Fallback local (notebook + Cloudflare Tunnel)

Só usar se a Oracle estiver genuinamente fora do ar e for uma emergência.
```bash
cd "TABBY SDP"
podman-compose -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.quicktunnel.yml up -d
podman logs tabbysdp_cloudflared_1 2>&1 | grep -A2 "trycloudflare"
```
A URL do Cloudflare Tunnel muda a cada restart — sempre pegar do log, nunca reusar link antigo.

## Reportar

Resumo direto: o que estava down (se algo estava), o que foi feito, e o resultado do teste final. Se estiver tudo certo desde o início, só confirmar em uma linha — não narrar o processo inteiro.

## Fora do escopo desta skill

- Mudar shape/instância da Oracle, billing, ou infraestrutura — decisão do Leo.
- Configuração do roteador Vivo (só relevante se algum dia voltar a usar aquele caminho) — documentado no `FALLBACK_RUNBOOK.md`.
- Rodar `sudo` local (firewalld etc.) — sempre pedir pro Leo rodar via `!`, nunca tentar contornar. (Na VM Oracle, `sudo` via SSH funciona normal, não tem essa restrição.)
