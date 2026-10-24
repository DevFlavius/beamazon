# Beamazon: regras para agentes

Beamazon é um mod do BeamNG.drive (modo carreira): o jogador compra vans elétricas autônomas que fazem entregas sozinhas e viram uma empresa de frota que ele gerencia. Ideia do Flavio e do irmão dele, Bernardo. Plano completo em `docs/plano.md`.

## Papéis

- Flavio e Bernardo decidem o gameplay, a economia e o que conta como "pronto". Eles não escrevem código.
- O agente cuida do código, da arquitetura e dos testes. Decisão de gameplay ou de balanceamento: apresente as opções com o trade-off e espere a escolha deles.

## Onde fica cada coisa

| O quê | Caminho |
|---|---|
| Este repo (fonte da verdade) | `~/Projects/Repositorios/beamazon/` |
| Conteúdo do mod (o que o jogo carrega) | `mod/` deste repo |
| Link que o jogo enxerga | `~/.local/share/BeamNG/BeamNG.drive/current/mods/unpacked/beamazon` → `mod/` |
| Código do jogo (só leitura) | `~/.local/share/Steam/steamapps/common/BeamNG.drive/` |
| Pasta do usuário (log, mods) | `~/.local/share/BeamNG/BeamNG.drive/current/` |
| Log do jogo | `~/.local/share/BeamNG/BeamNG.drive/current/beamng.log` |
| RLS Career Overhaul instalado (referência) | `mods/rls_career_overhaul_v2.8.0.zip` na pasta do usuário (leia com `unzip -p`) |

Versão do jogo: **0.40.3**. Na raiz do jogo, `NOTE_FOR_MODDERS.md` traz as regras oficiais. Leia esse arquivo antes da primeira mudança em `mod/`.

O `.claude/settings.local.json` (fora do git) já dá acesso de leitura à pasta do jogo e à pasta do usuário. Em outro PC, ajuste os caminhos nele.

## Regras do BeamNG (inegociáveis)

- **Nunca escreva na pasta do jogo.** Tudo o que o mod tem fica em `mod/`.
- **Não sobrescreva arquivos vanilla nem do RLS.** O mod só adiciona extensões novas e chama as funções existentes.
- **Só use funções que existem em `lua/` do jogo.** Se não achar lá, não existe. Antes de criar um arquivo, ache um arquivo do mesmo tipo no jogo e siga a estrutura dele.
- Lua é LuaJIT (5.1). Log: `log('I', 'beamazon', 'mensagem')`.
- Use os helpers do jogo (`lua/common/utils.lua`, `lua/common/mathlib.lua`, `lua/ge/ge_utils.lua`).
- Nomes únicos, sempre com prefixo `beamazon`. Um arquivo em `mod/lua/ge/extensions/beamazon/fleetSim.lua` carrega como a extensão `beamazon_fleetSim`.
- O zip de release só pode ter conteúdo do mod. README, notas e docs ficam fora de `mod/`.

## Arquitetura (decidida no plano)

`mod/lua/ge/extensions/beamazon/`:

- `adapter.lua`: a **única** camada que conhece nomes internos da carreira (ofertas, dinheiro, save, garagens, RLS). Quando o jogo atualizar, o conserto fica neste arquivo.
- `fleetManager.lua`: a frota, compra, upgrades e persistência no save.
- `fleetSim.lua`: simulação abstrata, com cada van como uma tabela Lua e um tick a cada 1 a 5 s (nunca por frame), incluindo o progresso offline (com teto).
- `fleetEconomy.lua`: receita pela tabela vanilla de entregas, menos energia, desgaste, comissão e seguro.
- `fleetVisual.lua`: fase 4, opcional, spawna de 1 a 3 vans robô perto do jogador.
- A UI vem na fase 3 (computador da garagem; celular do RLS quando ele estiver presente).

A frota **não existe fisicamente** no mapa. As vans vivem como dados. Isso é decisão de desempenho, não reabra.

O mod funciona sozinho. Se detectar o RLS, o `adapter` usa o celular, as garagens e a economia dele. Ele nunca depende do RLS para carregar.

## Ciclo de teste

1. Edite em `mod/`. O jogo lê pelo link, sem copiar nada.
2. No jogo: `Ctrl+L` recarrega o Lua do jogo e `~` abre o console.
3. Confira o `beamng.log` (`grep -i frota`). Só está pronto com o console limpo e com o mod testado **sozinho** (sem o RLS) e também com o RLS.
4. Release: `scripts/pack.sh` gera `dist/beamazon.zip`.

O agente não consegue rodar o jogo. Peça ao Flavio para testar e colar o trecho do log.

## Fase atual: 0 (exploração)

Mapeie no código da 0.40.3 e anote em `docs/api-jogo.md` (com caminho e linha):

- `career/modules/delivery/` (`generator.lua`, `general.lua`, `progress.lua`, `parcelManager.lua`): como as ofertas são geradas e quanto pagam.
- `career/modules/payment.lua` e `playerAttributes.lua`: como o dinheiro entra no saldo.
- Os hooks de save/load do perfil da carreira.
- `career/modules/inventory.lua`: slots de garagem e propriedades.
- A van robô: nome interno e config (procure nos `vehicles/` dentro de `content/vehicles/*.zip`).
- O RLS: como um addon registra um app no celular (`gameplay/overhaul/career/owners/overhaul_phone_apps_*.json`) e como detectá-lo com segurança.

Entregável da fase 0: o `docs/api-jogo.md` preenchido e um "hello world" (`beamazon_adapter` que credita $1 no saldo por comando de console).

## Decisões em aberto (dos irmãos, não do agente)

- Localização da van: **A**, só a quantidade de vagas conta; ou **B**, cada van atende a região da propriedade onde está.
- Os números de balanceamento (metas iniciais em `docs/plano.md`).
