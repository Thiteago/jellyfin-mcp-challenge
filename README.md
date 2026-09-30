# Jellyfin MCP Challenge

Dois serviços Ruby/Rails independentes:

- **`mcp_server/`** (porta 3001) — servidor MCP que expõe 8 tools sobre a biblioteca do Jellyfin (+ pedidos de mídia via [Seerr](https://docs.seerr.dev/)), usando a gem [`fast-mcp`](https://github.com/yjacquin/fast-mcp).
- **`agent_api/`** (porta 3010) — API que recebe uma pergunta em português, usa o Gemini (function calling) para decidir se/quais tools chamar no `mcp_server`, e devolve a resposta final. Também serve uma UI de chat simples em `/` (`public/index.html`, puro HTML/JS, sem build step) pra testar sem precisar de curl.

## Como os dois se conversam

```
usuário
  │  POST /api/questions {"question": "..."}
  ▼
agent_api
  │  1. GET  /mcp/sse       (mcp_server)  → abre stream SSE, recebe endpoint de mensagens
  │  2. POST /mcp/messages  tools/list    → descobre as tools disponíveis
  │  3. POST generateContent (Gemini)     → pergunta + lista de tools
  │  4. Gemini responde com um functionCall (ou várias)
  │  5. POST /mcp/messages  tools/call    → executa a tool no mcp_server (que fala com o Jellyfin real)
  │  6. POST generateContent (Gemini)     → devolve o resultado da tool (functionResponse)
  │  7. repete 4-6 até o Gemini responder só texto
  ▼
resposta final + lista de tool_calls feitas
```

O `mcp_server` responde `tools/list`/`tools/call` de forma assíncrona: a resposta não vem no corpo do POST, é publicada no stream SSE aberto em `GET /mcp/sse` (transporte HTTP+SSE do `fast-mcp`). Por isso o `agent_api` mantém uma conexão SSE persistente (`app/services/mcp/client.rb`) e correlaciona pergunta/resposta pelo `id` do JSON-RPC.

## Tools do MCP Server

| Tool | O que faz |
|---|---|
| `random_movie` | Sorteia um filme (filtros opcionais: gênero, só não-assistidos) |
| `search_media` | Busca filmes por título/gênero/ano |
| `get_media_details` | Sinopse, elenco, duração e nota de um filme |
| `mark_as_favorite` | Marca um filme como favorito |
| `get_active_sessions` | Quem está assistindo o quê agora no servidor |
| `movie_night_roulette` | Sorteia um filme + sugestão de pipoca/bebida pelo gênero |
| `request_media` | Pede um filme/série que não está no Jellyfin via **Seerr** — dispara o download automático no *arr stack. Idempotente: se já estiver pendente/baixando/disponível, só informa o status em vez de duplicar o pedido |
| `check_media_status` | Consulta o status de um título no Seerr (nunca pedido / pendente / baixando / disponível) sem disparar nada — usado antes de `request_media` pra não perguntar/duplicar pedido de algo que já está em andamento |

## Setup

Requer Ruby 3.2+ e uma instância Jellyfin acessível.

```bash
# 1. mcp_server
cd mcp_server
cp .env.example .env   # preencha JELLYFIN_URL, JELLYFIN_API_KEY, JELLYFIN_USER_ID, SEERR_URL, SEERR_API_KEY
bundle install
bin/rails s -p 3001

# 2. agent_api (em outro terminal)
cd agent_api
cp .env.example .env   # preencha GEMINI_API_KEY (o resto já aponta pro mcp_server local)
bundle install
bin/rails s -p 3010
```

`JELLYFIN_USER_ID` é o ID do usuário Jellyfin cujas tools vão operar — pegue em Painel Admin > Usuários (ou via `GET {JELLYFIN_URL}/Users` com a API key). `JELLYFIN_API_KEY` é gerada em Painel Admin > Avançado > API Keys (autenticação via header `Authorization: MediaBrowser Token="..."`, o `X-Emby-Token` legado não é mais aceito no Jellyfin 12.x). `SEERR_API_KEY` é gerada em Seerr > Configurações > Geral. `GEMINI_API_KEY` em https://aistudio.google.com/apikey.

`MCP_AUTH_TOKEN` precisa ser o **mesmo valor** nos dois `.env` (protege o `mcp_server` de chamadas não autenticadas).

## Testando

Com os dois serviços rodando, abra **http://localhost:3010** no navegador pra usar o chat direto (melhor forma de demonstrar no pitch). Também dá pra usar curl:

```bash
# Sanity check isolado do MCP server (sem depender do Gemini)
curl -N http://localhost:3001/mcp/sse -H "Authorization: Bearer dev-secret-token" &
curl -X POST http://localhost:3001/mcp/messages \
  -H "Content-Type: application/json" -H "Authorization: Bearer dev-secret-token" \
  -d '{"jsonrpc":"2.0","id":"1","method":"tools/list","params":{}}'
# a resposta aparece no stream SSE aberto no comando de cima, não neste POST

# Fluxo completo via agent_api
curl -X POST http://localhost:3010/api/questions \
  -H "Content-Type: application/json" \
  -d '{"question": "Sorteia um filme de terror pra noite de hoje e me conta a sinopse e o elenco"}'
```

Perguntas boas para demonstrar no pitch:
- *"Quem está assistindo alguma coisa agora?"* → só `get_active_sessions`.
- *"Sorteia um filme de comédia que eu ainda não assisti"* → `random_movie` com os filtros certos.
- *"Sorteia um filme de terror pra hoje e me conta a sinopse e o elenco"* → encadeia 2 tools (o resultado da primeira alimenta a segunda).
- *"Marca [filme] como favorito"* → ação de escrita real no Jellyfin.
- *"Pede pra baixar o filme [título] que não tenho"* → busca no Seerr e cria o pedido (dispara o *arr stack de verdade).
- *"Qual a capital da França?"* → não deve chamar nenhuma tool.

## Notas de implementação

- O `fast-mcp` só serializa o retorno de uma tool como JSON de verdade se for um Hash com chave `:content` — daí o helper `ApplicationTool#respond_with` usado em todas as tools.
- O schema de argumentos gerado pelo `dry-schema` (via `fast-mcp`) inclui chaves como `not`/`minLength` que a API do Gemini não aceita nos parâmetros de function calling; `Agent::QuestionAnswerer#sanitize_schema` filtra isso antes de montar a `functionDeclaration`.
- Usamos o `generateContent` clássico (não a nova Interactions API do Gemini, ainda instável para os fins deste desafio) — `contents` com parts `functionCall`/`functionResponse`. Atenção: nem todo modelo aceita `role: "function"` para devolver o resultado da tool — nesse projeto usamos `role: "user"` mesmo pra isso (o Gemini retornou os papéis válidos no erro 400 quando tentamos `"function"`).
- `gemini-2.5-flash` parou de ficar disponível pra API keys novas; o modelo atual usado aqui é `gemini-3.8-flash`.
- O encoder padrão de query params do Faraday escapa espaço como `+`, mas a API do Seerr rejeita isso e exige `%20` literal — `Seerr::Client::PercentParamsEncoder` resolve isso.
- `RequestMediaTool` não usa o servidor Radarr/Sonarr padrão do Seerr cegamente: antes de criar o pedido, consulta `/service/radarr` (ou `/sonarr`) e escolhe o **servidor** (`serverId`) cujo diretório padrão tem mais espaço livre — não só a pasta (`rootFolder`) isolada. No setup do desafio, cada servidor (`radarr-e`/`radarr-d`) amarra pasta + tag do qBittorrent (usada pra rotear o download pro disco certo); sobrescrever só o `rootFolder` mantendo o servidor padrão deixaria path e tag dessincronizados.
- `Mcp::Client.shared` mantém uma conexão SSE única por processo do `agent_api`. Se o `mcp_server` for reiniciado, essa conexão fica órfã; `Mcp::Client#send_request` detecta o timeout e reconecta automaticamente antes de tentar de novo (uma única vez).
