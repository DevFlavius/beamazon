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
- A UI vem na fase 3, como app no celular do RLS.

A frota **não existe fisicamente** no mapa. As vans vivem como dados. Isso é decisão de desempenho, não reabra.

**O Beamazon é um addon do RLS** (decisão do Flavio, 2026-10-24: suportar os dois dobraria teste e validação). Só o caminho com o RLS é desenvolvido e testado: celular, garagens e economia dele. Sem o RLS, o mod carrega, avisa no log e não faz nada, sem erro. O suporte à carreira vanilla pode voltar no futuro; por isso o `adapter` continua sendo a única camada que fala com a carreira.

## Ciclo de teste

1. Edite em `mod/`. O jogo lê pelo link, sem copiar nada.
2. No jogo: `Ctrl+L` recarrega o Lua do jogo e `~` abre o console.
3. Confira o `beamng.log` (`grep -i beamazon`). Só está pronto com o console limpo e testado com o RLS. Antes de cada release, confira também que, sem o RLS, o mod carrega sem erro e fica parado.
4. Release: `scripts/pack.sh` gera `dist/beamazon.zip`.

O agente não consegue rodar o jogo. Peça ao Flavio para testar e colar o trecho do log.

O jogo demora a carregar, então os testes vão em lotes. A fila fica em `docs/testes.md`:

- **Crítico** (dinheiro, save, ou algo que pode impedir o mod ou a carreira de carregar): vai para o próximo lote de teste, pequeno.
- **Não crítico** (UI, texto, estatística, log): acumula e é testado junto.

Toda mudança em `mod/` entra na fila com a categoria e os passos. Item testado sai da fila e vira uma linha em "Testado".

## Fase atual: 1 (MVP)

Fase 0 concluída em 2026-10-24: `docs/api-jogo.md` preenchido e `beamazon_adapter.creditTest()` testado em jogo.

O MVP (1 van abstrata, compra por console, simulação por timer, pagamento real no saldo, save) funciona em jogo (2026-10-24, com o RLS): compra, entregas, pagamento no saldo, gravação em `<save>/career/beamazon.json` e a frota volta ao recarregar o save. Medido em jogo: ~$142 de lucro por van-hora, porque a economia viva do RLS paga menos que a fórmula base (ela já inclui a dificuldade do save: difícil e hardcore pagam ×0,5). Os números de balanceamento esperam a decisão dos irmãos. Comandos no console (GE Lua):

- `beamazon_fleetManager.buyVan()`: compra uma van.
- `beamazon_fleetManager.status()`: mostra a frota no log, com o lucro por van-hora depois de 1 van-hora de trabalho.
- `beamazon_fleetSim.setSpeed(60)`: acelera a frota para teste (1 s de jogo = 1 min de frota; não é salvo).

Fase 2, peças que não dependem de balanceamento (2026-10-24, testadas só no RLS simulado):

- **Progresso offline:** o save guarda `savedAt` (hora real). Ao carregar, a frota trabalha o tempo que o jogador ficou fora, até `offlineCapHours` (8 h), e o lucro entra num lançamento só ("offline deliveries").
- **Pagamento em lote:** o lucro das viagens entra no saldo num lançamento por minuto de jogo e logo antes de cada save. A linha de cada viagem no log ficou no nível `D`.

Fase 3, primeira versão (2026-10-24, compilada e testada só fora do jogo): app "Beamazon" no celular do RLS, instalado pela App Store. Mostra a frota (vans, entregas, lucro), cada van com o progresso da viagem, e tem o botão de comprar van. Lua em `phoneApp.lua`, tela em `mod/ui/ui-vue/mods/beamazon/PhoneBeamazon.vue`.

Balanceamento decidido em 2026-10-24: as vans de pessoa física são liberadas pelo nível de Logística do RLS (5, 10 e 15 dão 1, 2 e 3 vans; o 20 libera a empresa) e a van custa em média $7.500, com o sorteio de preço das concessionárias do RLS. Ideias da empresa (caminhão com motorista, funcionários, sedes em pontos do mapa) no roadmap em `docs/plano.md`.

Todos os números de balanceamento ficam em `mod/lua/ge/extensions/beamazon/balance.lua`. São provisórios até os irmãos decidirem.

Teste da lógica sem o jogo: `cd tests && npm install && npm test` roda os módulos contra um RLS simulado (Lua em JavaScript, `fengari`). Rode depois de cada mudança em `mod/`. Ele não substitui o teste em jogo nem mede balanceamento (a fórmula de pagamento ali é uma cópia, sem a economia viva do RLS).

## Decisões em aberto (dos irmãos, não do agente)

- Os números de balanceamento (metas iniciais em `docs/plano.md`), inclusive os da empresa e das filiais.

Decididas (2026-10-24, detalhes em `docs/plano.md`, "Empresa de entregas"): localização **A** (as vans atendem o mapa todo); pessoa física até 3 vans; acima disso, uma empresa com XP próprio e árvore de upgrades; filial é um lugar no mapa que soma vagas; a frota dá muito pouco XP de Logística ao jogador.
