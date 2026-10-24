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

> **Substituído (2026-10-24):** as vans de pessoa física vêm do nível de Logística e, na empresa, as vagas vêm das sedes e filiais, pontos do mapa com computador (ver "Empresa de entregas"). As vagas não estão mais ligadas às garagens do RLS. O texto abaixo fica só como histórico.

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

- **Pessoa física:** até 3 vans, sem empresa. Feito; desde a nota abaixo, liberadas pelo nível de Logística.
- **Empresa:** para passar de 3 vans, o jogador abre uma empresa. O nível dela mistura duas coisas: **XP próprio da empresa**, ganho pelas entregas da frota, e uma **árvore de upgrades** no modelo das empresas do RLS (o RLS lê as árvores de `gameplay/overhaul/business/skillTrees/*.json`, então o addon pode trazer a sua). Cada nível sobe o limite de vans e a eficiência das entregas, e talvez o pagamento. Há muitos níveis, então cada um libera pouco (exemplo: +2 vans; nível 1 = 10 vans).
- **XP de Logística do jogador:** a frota dá muito pouco, de propósito (`balance.fleetXpShare`, 2% do XP que um motorista ganharia; provisório). O jogador não pode subir de nível parado.
- **Filial:** um lugar no mapa, comprado com garagens e vagas. Ela soma vagas para vans.
- **Localização: A.** As vans atendem o mapa todo; a filial não limita a região das entregas.

Ordem: 1) limite de pessoa física (feito); 2) a empresa com nível e upgrades; 3) as filiais.

Decidido pelo Flavio e pelo Bernardo em 2026-10-24 (balanceamento):

- **Vans de pessoa física pelo nível de Logística do RLS:** nível 5 libera a 1ª van, 10 a 2ª e 15 a 3ª. Feito (`balance.personalVanUnlocks`). O RLS lê esse nível pelo caminho `careerSkills-logistics` (nível 5 = 1.400 XP, 10 = 5.300, 15 = 13.000, 20 = 26.000).
- **Nível 20 de Logística** libera a compra do ponto de empresa mais básico (a sede).
- **Preço da van: média de $7.500**, variando como as concessionárias do RLS. Feito. O RLS sorteia cada anúncio: 98% caem entre 88% e 112% do preço base, 1% vai até 70% e 1% até 130%; depois aplica o índice vivo do mercado de veículos. O Beamazon faz o mesmo: a oferta da próxima van fica no save (recarregar não sorteia de novo) e muda a cada compra.
- **Exemplo de capacidade da primeira empresa:** 10 vans e 1 caminhão, ou 9 vans e 1 caminhão.

### Roadmap de ideias (Flavio e Bernardo, 2026-10-24)

- **Caminhão pequeno (H-Series), ~$18.000.** Bem mais eficiente que a van: entregas maiores e mais longas, que pagam mais. Não é autônomo: precisa de um **motorista contratado**, com salário proporcional ao que o caminhão rende. Dá para desativar: demite o motorista e o caminhão fica parado no estoque, sem renda e sem custo.
- **Funcionários.** O RLS tem contratação nos negócios: a oficina de tuning (`business/tuningShop/techs.lua`) contrata e demite técnicos, com vagas que crescem pela árvore de habilidades, mas sem salário e presa à oficina. Não dá para reaproveitar direto; o Beamazon segue o mesmo modelo (vagas pela árvore, contratar, demitir) com o salário próprio dele.
- **Sedes e filiais em pontos reais do mapa:** só adicionamos um computador (ponto de interação do RLS, com função própria no menu do computador). A primeira sede fica no ponto "Logistics" (`-126.627, 36.444, 122.440`); o prédio de tijolo das Dockyards fica para depois.
- **Tenda no lugar da barreira** na sede (spawn e esconder em tempo de execução), depois que o computador funcionar.

Decidido pelo Flavio e pelo Bernardo em 2026-10-24 (segunda rodada):

- **Vaga é vaga.** Van e caminhão ocupam uma vaga cada. O limite é o das vagas da filial (a regra **b**).
- **Primeira filial: umas 5 vagas** (10 pareceu muito; o número ainda é exemplo).
- **Caminhões limitados por motoristas.** Na primeira filial dá para ter 5 caminhões, se houver 5 motoristas. O custo do motorista é a desvantagem do caminhão.
- **Motoristas pela árvore de habilidades da empresa.** Exemplo: ao comprar a filial, 1 motorista (1 caminhão e 4 vans); a árvore libera mais motoristas com o tempo, e o jogador pode vender uma van para pôr outro caminhão.
- **Venda de van:** segue o mercado, como a compra. O valor parte do preço pago, com desvalorização, e passa pelo índice de venda do RLS (o RLS paga 95% do índice na venda, ou 85% quando o mercado está abaixo de 0,85).
- **Árvore de habilidades:** viável. No RLS ela é só dados: um JSON por tipo de negócio em `gameplay/overhaul/business/skillTrees/` com nós (custo em dinheiro, custo em XP da empresa, nível máximo, dependências), e `business/skillTree.lua` cobra e grava. Caminho a escolher pelo agente: registrar a empresa como um tipo de negócio do RLS (ganha a tela da árvore, a conta e o computador prontos, mas fica preso aos internos dos negócios do RLS) ou uma árvore própria no mesmo formato, dentro do app do Beamazon.

Ainda a decidir com o Bernardo: o salário do motorista e os números do caminhão; o preço de abrir a empresa; quanto a van desvaloriza (por tempo, por entregas, ou as duas); o XP por nível; o preço das filiais e as vagas de cada uma; se a frota ganha o bônus de pagamento do nível de Logística do jogador (o agente sugere que não: a empresa tem o bônus dela).

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

Atualizado em 2026-10-24. As fases 0 a 3 do plano original viraram os blocos "Feito" abaixo.

### Feito

1. **Exploração (fase 0):** API do jogo e do RLS mapeada em `docs/api-jogo.md`.
2. **MVP (fase 1):** compra de van, entregas abstratas, pagamento no saldo, save. Testado em jogo.
3. **Peças da fase 2:** progresso offline (teto de 8 h), pagamento em lote, lucro por van-hora, um pouco de XP de Logística. Testado em jogo.
4. **App no celular (fase 3, v1):** frota, progresso das viagens, botão de compra. Testado em jogo.
5. **Balanceamento, rodada 1:** vans pelo nível de Logística (5, 10, 15) e preço médio de $7.500 com o sorteio e o mercado do RLS. Testado em jogo (falta o item 9b).

### Próximo: a empresa (decidido, falta fazer)

6. **Venda de van:** parte do preço pago, desvaloriza e segue o índice de venda do RLS. Espera a regra de desvalorização.
7. **Sede:** o nível 20 de Logística libera a compra; computador no ponto "Logistics"; umas 5 vagas; vaga é vaga (van ou caminhão).
8. **XP e árvore de habilidades da empresa:** a frota dá XP à empresa; a árvore libera motoristas, vagas e eficiência.
9. **Caminhão H-Series (~$18.000) e motoristas:** entregas maiores e mais longas; cada caminhão precisa de um motorista com salário; sem motorista, fica parado sem custo.
10. **Filiais:** outros pontos do mapa (as Dockyards primeiro), cada uma com as suas vagas.
11. **Tenda na sede**, no lugar da barreira.

### Depois (do plano original, ainda sem decisão)

12. **Custos que faltam:** seguro por dia de jogo; revisão periódica, com pane se atrasar.
13. **Upgrades por van:** motor, bateria, baú, software de rota.
14. **Contra o dinheiro infinito:** retorno decrescente com muitas vans; eventos aleatórios (pane, acidente, reclamação).
15. **Vitrine (fase 4):** de 1 a 3 vans robô andando perto do jogador, opcional.
16. **Release:** checagem sem o RLS, zip, publicação.
17. **Expansão (fase 5):** outros mapas e, se compensar, a carreira vanilla.

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
