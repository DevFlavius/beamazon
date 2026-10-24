# Plano: Beamazon, frota de vans autônomas (modo carreira)

Cópia do plano feito no claude.ai em 2026-10-24 ([documento original](https://claude.ai/artifact/9b7Lfy8hr99qCxTq17abVn)). Daqui em diante, **este arquivo é a fonte da verdade**: decisões novas entram aqui.

## Resumo da ideia

O mod é viável. As vans robô já existem no jogo como veículo de tráfego simplificado, e o sistema de entregas da carreira é todo em Lua, então dá para estendê-lo. Para escalar, a frota é simulada "no papel" em vez de cada van rodar fisicamente.

- O jogador compra vans elétricas autônomas e as coloca para fazer entregas sozinhas.
- Cada entrega gera receita. A frota vira uma renda passiva que cresce com o número de vans.
- A graça está na gestão: configurar a van (motor, bateria, consumo), escolher rotas e tipos de carga, equilibrar custos.
- Precisa existir custo recorrente (energia, manutenção, comissão), senão vira dinheiro infinito sem decisão nenhuma.
- O desempenho do PC não pode cair conforme a frota cresce.

## Viabilidade técnica

Tudo o que o mod precisa é acessível via Lua. O maior risco é a API interna da carreira mudar entre versões do jogo.

| Peça | O que existe hoje | Uso no mod |
|---|---|---|
| Versão do jogo | 0.40.3 (instalada); a 0.39 saiu em 29/07/2026 | Alvo inicial |
| Van robô | Van de tráfego simplificado, adicionada no início de 2026 | Modelo visual da frota |
| Veículos simplificados | Física jbeam e modelos reduzidos ([docs](https://documentation.beamng.com/official_content/vehicles/simplifiedtrafficvehicles)) | Vans "de vitrine" opcionais |
| Sistema de entregas | Lua em `lua/ge/extensions/career/modules/delivery/` | Fonte das ofertas e dos valores pagos |
| Override de módulos | Arquivo com o mesmo caminho substitui o original | **Evitar**; usar extensão própria |
| Capacidade de carga | Seção `cargoStorage` no jbeam ([docs](https://documentation.beamng.com/modding/vehicle/sections/cargostorage)) | Quantos volumes cada van leva |
| Precedente | O RLS já adiciona negócios, empréstimos e uma loja de tuning | Prova de que negócio na carreira é possível |

Pontos de atenção:
- A 0.39 reestruturou as rotas e a UI da carreira, e o RLS precisou migrar. Conte com retrabalho a cada versão grande.
- As funções de pagamento, save e ofertas não são API documentada; os nomes vêm da leitura do código (`docs/api-jogo.md`).

## Economia

Regra de ouro: uma van rende bem menos por hora do que o jogador dirigindo, e o lucro só cresce com boas decisões de gestão.

```
lucro = R − (d · c · p_kWh) − (d · m) − (R · t)
```

- `R`: o valor que o sistema vanilla pagaria pela entrega (já considera distância e tipo de carga).
- `d`: distância (km).
- `c`: consumo (kWh/km).
- `p_kWh`: preço da energia.
- `m`: desgaste por km.
- `t`: comissão da plataforma.

| Custo | Tipo | Como o jogador influencia |
|---|---|---|
| Compra da van | Único | Escolhe o modelo e a quantidade |
| Energia | Por km | Upgrade de motor e bateria reduz o consumo |
| Manutenção e desgaste | Por km, acumula até a revisão | Com revisões em dia não há pane (van parada não fatura) |
| Comissão da plataforma | % por entrega | Cai com reputação ou contrato melhor |
| Seguro | Fixo por dia de jogo | Sem seguro, um acidente simulado custa caro |
| Vaga no depósito | Fixo por van | Limita a escala até comprar um depósito maior |

Upgrades:
- **Motor:** menos consumo por km.
- **Bateria:** mais entregas antes de recarregar.
- **Baú:** mais capacidade, aceita entregas que pagam mais.
- **Software de rota:** entregas mais curtas, menos tempo ocioso.

Limites contra dinheiro infinito:
- As vans disputam as mesmas ofertas que o jogador, e muitas vans esgotam as boas.
- O retorno é decrescente: cada van extra na mesma região pega ofertas piores.
- Eventos aleatórios (pane, acidente, cliente reclamando) trazem custo e tempo parado.
- Metas iniciais, a ajustar em teste: a van se paga em 3 a 5 horas reais de jogo e rende de 20% a 35% do que o jogador ganha dirigindo no mesmo tempo.

## Slots e depósitos

A frota usa **vagas de frota próprias**, ligadas às propriedades do jogador, e não os slots de carro da garagem (a maior garagem tem uns 10 slots, e a frota tiraria espaço dos carros pessoais).

- A primeira propriedade libera 1 ou 2 vans.
- Cada propriedade nova soma vagas, proporcionais ao tamanho dela.
- Propriedade alugada ou financiada vale enquanto o contrato estiver ativo. Se o jogador perder a propriedade, as vans vão para um pátio com diária.
- O depósito de frota, um imóvel exclusivo do mod, dá mais vagas e carregadores, com custo fixo maior.
- Os upgrades da empresa aumentam as vagas por propriedade.

Exemplo com vagas de frota = metade dos slots, arredondando para cima (garagens do RLS):

| Garagem (RLS) | Slots de carro | Vagas de frota |
|---|---|---|
| Chinatown Garage | 2 | 1 |
| Sealbrick 1058 Garage | 3 | 2 |
| Cul-de-Sac Garage | 5 | 3 |
| Belasco Auto Garage | 8 | 4 |
| Commercial Garage | 15 | 8 |

### Empresa de entregas

A frota é uma empresa que evolui, no modelo do Tuning Shop do RLS (conta e XP próprios, árvore de habilidades). Ganha XP por entrega e desbloqueia vagas, contratos melhores e comissão menor.

Decidido pelo Flavio em 2026-10-24 (nota de voz):

- **Pessoa física:** até 3 vans, sem empresa. Feito (`balance.personalVanLimit`).
- **Empresa:** para passar de 3 vans, o jogador abre uma empresa. O nível dela mistura duas coisas: **XP próprio da empresa**, ganho pelas entregas da frota, e uma **árvore de upgrades** no modelo das empresas do RLS (o RLS lê as árvores de `gameplay/overhaul/business/skillTrees/*.json`, então o addon pode trazer a sua). Cada nível sobe o limite de vans e a eficiência das entregas, e talvez o pagamento. Há muitos níveis, então cada um libera pouco (exemplo: +2 vans; nível 1 = 10 vans).
- **XP de Logística do jogador:** a frota dá muito pouco, de propósito (`balance.fleetXpShare`, 2% do XP que um motorista ganharia; provisório). O jogador não pode subir de nível parado.
- **Filial:** um lugar no mapa, comprado com garagens e vagas. Ela soma vagas para vans.
- **Localização: A.** As vans atendem o mapa todo; a filial não limita a região das entregas.

Ordem: 1) limite de pessoa física (feito); 2) a empresa com nível e upgrades; 3) as filiais.

Números ainda a decidir com o Bernardo: o preço de abrir a empresa, o limite por nível, o XP por nível, o preço das filiais e quantas vagas cada uma dá.

## Integração com o RLS

**Decisão (Flavio, 2026-10-24): o Beamazon é um addon do RLS.** Suportar a carreira vanilla e o RLS ao mesmo tempo dobraria teste e validação. Sem o RLS, o mod carrega, avisa no log e fica parado. A carreira vanilla pode entrar depois, na expansão.

| Recurso | Com RLS |
|---|---|
| Interface | App no celular do RLS, com página no app de guia |
| Vagas de frota | Garagens do app Real Estate, inclusive alugadas e financiadas |
| Dinheiro | Conta da empresa separada |
| Preços | Economia viva do RLS |
| Compra de vans | À vista ou por empréstimo do RLS |
| Modo hardcore | Receita reduzida, seguindo a regra do RLS |

O que já se sabe: a UI do RLS é Vue (fonte em `ui-vue-src`), o celular tem apps de negócios e de guia, e o modo de desafios tem API para outros mods. Addons de terceiros já penduram negócios no RLS ([RLS Dealership](https://www.beamng.com/resources/rls-dealership-for-rls-v2-7-1-1.39524/), [RLS garage valet](https://beamng.com/resources/rls-garage-valet.39782/)).

Achado no RLS 2.8.0 (2026-10-24): cada negócio é um tipo declarado em `gameplay/overhaul/business/types/<id>.json` (`engineShop`, `passiveBusiness`, `racingTeam`, `tuningShop`), que aponta para um módulo Lua e abas Vue do computador de negócios. Nenhum deles é empresa de entrega. O `passiveBusiness` (lojas com renda passiva, estoque, finanças e upgrades) é o modelo mais próximo do mod; a frota pode virar um tipo novo de negócio. A pasta `business/fleet/` do RLS é só a garagem de veículos dos negócios, não entregas.

A confirmar no código (o RLS 2.8.0 está instalado):
- Como um addon registra um app novo no celular (pistas: `gameplay/overhaul/career/owners/overhaul_phone_apps_*.json`).
- Como detectar o RLS com segurança (extensão carregada, sem depender do nome do arquivo).
- Se a 2.8.0 já roda na 0.40.
- Vale contatar os devs do RLS no GitHub antes da UI.

## Arquitetura

Uma extensão Lua própria, sem sobrescrever arquivos vanilla, com todas as chamadas ao jogo isoladas numa camada de adaptação.

```
Jogo BeamNG (vanilla): sistema de entregas · dinheiro e save · tráfego e IA
        ↕  ofertas, pagamento, spawn
adapter: único ponto que conversa com o jogo (e com o RLS)
        ↕  chamadas internas do mod
Núcleo: fleetManager (frota, compra, upgrades, save)
        fleetSim (tick de 1 a 5 s, entregas abstratas)
        fleetEconomy (receita vanilla, energia, desgaste, comissão)
        ↕                           ↕
App da frota (celular/computador)   fleetVisual (1 a 3 vans robô, opcional)
```

## Desempenho

A frota não existe fisicamente. 50 vans como registros de dados custam quase nada, enquanto 50 vans spawnadas derrubam o FPS (há relatos de queda com só uns 5 carros de tráfego em PC fraco).

- **Simulação abstrata:** cada van é uma tabela Lua (posição lógica, carga, bateria, desgaste, entrega atual).
- **Tick espaçado:** de 1 a 5 s, nunca por frame.
- **Vitrine opcional:** no máximo de 1 a 3 vans reais perto do jogador, configurável.
- **Progresso offline:** ao carregar o save, calcula o que a frota fez com o jogador fora, com teto contra exploit. (Os irmãos curtiram muito essa.)

## Roadmap

Comece por um MVP sem UI bonita nem vans visíveis. O que valida a ideia é provar que a frota gera e gasta dinheiro de forma equilibrada.

0. **Exploração (1 a 2 semanas):** mapear as entregas, o dinheiro, o save/load e os slots no código da 0.40 e testar no console.
1. **MVP (2 a 4 semanas):** 1 van abstrata, compra por comando de console, simulação por timer, pagamento real no saldo e persistência no save.
2. **Economia:** energia, desgaste, comissão e seguro; planilha de balanceamento; testes com 1, 5 e 20 vans.
3. **Interface:** app no computador/celular com lista da frota, lucro por van, upgrades e alertas.
4. **Vitrine:** spawn opcional de vans robô perto do jogador.
5. **Expansão:** depósitos, eventos aleatórios, cargas extras, outros mapas e, se compensar, a carreira vanilla sem o RLS.

| Risco | Impacto | Mitigação |
|---|---|---|
| Update do jogo quebra a API da carreira | Alto | Camada de adaptação; testar a cada versão |
| Conflito com o RLS ou outros mods de carreira | Médio | Não sobrescrever arquivos; só extensões novas |
| Update do RLS quebra o mod (somos addon dele) | Alto | Toda chamada ao RLS só no `adapter`; testar a cada versão do RLS |
| Público menor: só quem usa o RLS | Médio | Addons do RLS já são aceitos no repositório oficial (RLS Dealership, garage valet); vanilla fica para a expansão |
| Economia quebrada (dinheiro infinito) | Médio | Limite de ofertas, retorno decrescente, teto offline |
| A UI exige Vue e o roteador novo da 0.39 | Médio | Começar com um app simples; estudar a migração do RLS |
| Van robô não comprável no vanilla | Baixo | A frota abstrata não depende do veículo |

## Fontes

- [BeamNG.drive v0.39 Release Notes](https://beamng.com/game/news/patch/beamng-drive-v0-39/)
- [Simplified Traffic Vehicles](https://documentation.beamng.com/official_content/vehicles/simplifiedtrafficvehicles)
- [Cargo Storage](https://documentation.beamng.com/modding/vehicle/sections/cargostorage)
- [RLS Career Overhaul (GitHub)](https://github.com/RLS-Modding/rls_career_overhaul)
- [RLS v2.7: migração para 0.39](https://www.patreon.com/RacelessRLS/posts/rls-career-v2-7-166037472)
- [Fórum: override de módulos da carreira](https://www.beamng.com/posts/1680417/)
- [Fórum: FPS com tráfego](https://beamng.com/posts/1793244/)
