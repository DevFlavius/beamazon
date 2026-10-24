# API do jogo usada pelo mod

Funções reais da carreira (BeamNG.drive **0.40.3**, RLS Career Overhaul **2.8.0**) que o `adapter.lua` chama ou vai chamar. Cada item traz o caminho e a linha no código. Quando o jogo ou o RLS atualizar, revise esta lista primeiro.

Mapeado em 2026-10-24 lendo o código. Testado em jogo: `addMoney` com o RLS e na carreira vanilla. As funções do MVP (fase 1) também, com o RLS: `pay`, `getParcelTemplates`, `getParcelReward`, os três hooks e a gravação no save. Em jogo o RLS arredonda a receita para dólares inteiros.

Desde 2026-10-24 o Beamazon é addon do RLS e só o caminho do RLS é usado. As seções vanilla ficam como referência: o RLS reaproveita boa parte delas (entregas, por exemplo) e elas servem se o suporte vanilla voltar.

Caminhos curtos:

- `career/` = `lua/ge/extensions/career/` na pasta do jogo
- `delivery/` = `career/modules/delivery/`
- `RLS:` = arquivo dentro de `mods/rls_career_overhaul_v2.8.0.zip` (leia com `unzip -p`)

## Como o mod carrega

- [x] `core_modmanager` roda todo `scripts/*/modScript.lua` ao ativar um mod (`lua/ge/extensions/core/modmanager.lua:739`). Ele avisa no log se a extensão carregada ali não tiver `setExtensionUnloadMode(..., "manual")` antes (`modmanager.lua:719-737`).
- [x] `setExtensionUnloadMode(nome, "manual")` mantém a extensão viva na troca de mapa (`lua/ge/main.lua:425`).
- [x] O nome da extensão vem do caminho: `lua/ge/extensions/beamazon/adapter.lua` → `beamazon_adapter` (`lua/common/extensions.lua:55`, `luaPathToExtName`).
- [x] Nosso `mod/scripts/beamazon/modScript.lua` faz as duas chamadas para `beamazon_adapter`.
- Os módulos da carreira vanilla são achados por pasta (`career/career.lua:19`, `careerModuleDirectory`). Não colocamos nada lá: seria mexer no namespace do jogo.

## Carreira ativa

- [x] Vanilla: `career_career.isActive()` (`career/career.lua:336`).
- [x] RLS: `overhaul_career_career.isActive()` (`RLS: lua/ge/extensions/overhaul/career/career.lua:433`).
- **Com o RLS, a carreira é outra.** O RLS não usa `career_career` nem `career_saveSystem`; tem `overhaul_career_career` e `overhaul_career_saveSystem`, sem alias para os nomes vanilla (`RLS: gameplay/overhaul/ui/owners/overhaul_career_career.json` e `overhaul_career_saveSystem.json`, `"aliases": []`). O `adapter` escolhe o caminho por `isRlsPresent()`.

## Dinheiro

- [x] Crédito ou débito: `career_modules_playerAttributes.addAttributes(change, reason)` (`career/modules/playerAttributes.lua:66`).
  - `change = {money = 100}`; valor negativo debita.
  - `reason = {label = "texto ou chave de tradução", tags = {...}}`. Sem `reason`, o jogo loga um aviso (`:69-75`).
  - Dispara o hook `onPlayerAttributesChanged(change, reason)` (`:125`).
  - A tag `gameplay` com dinheiro desbloqueia a conquista "FIRST_ASSIGNMENT" (`:127-129`). O mod **não** usa essa tag.
- [x] Saldo: `career_modules_playerAttributes.getAttributeValue("money")` (`:148`).
- [x] Cobrança com checagem de saldo: `career_modules_payment.pay(price, reason)`, com `price = {money = {amount = 100, canBeNegative = false}}`; retorna `false` se não der (`career/modules/payment.lua:18`; `canPay` na `:9`).
- [x] RLS: `overhaul_career_economy_playerAttributes.addAttributes(change, reason, fullprice, onRecorded)` (`RLS: lua/ge/extensions/overhaul/career/economy/playerAttributes.lua:345`). Mesma assinatura nos dois primeiros argumentos. O RLS cria o alias `career_modules_playerAttributes` para esse módulo (`RLS: gameplay/overhaul/ui/owners/overhaul_career_economy_playerAttributes.json`), mas o `adapter` chama o nome do RLS direto.
- [x] RLS: o dinheiro passa por um livro-caixa. `reason.category` define a categoria do lançamento (`RLS: .../economy/playerAttributes.lua:445-446`); `"business"` é uma categoria válida (`RLS: lua/ge/extensions/overhaul/lib/ledger/categories.lua:8-25`). O vanilla ignora esse campo, então o `adapter` sempre manda `category = "business"`.
- [x] RLS: `payment.pay(price, reason, accountId, onRecorded)` aceita uma conta específica (`RLS: lua/ge/extensions/overhaul/career/economy/payment.lua:92`). Serve para a "conta da empresa" na fase 2. Retorna `false` se o saldo não cobre (`canPay`, `:67`); no modo cheats sempre cobre (`:80`). O `adapter.pay` usa essa função para a compra da van.

## Save / load

Vanilla:

- [x] Ao salvar: hook `onSaveCurrentProfile(savePath, vehiclesThumbnailUpdate)` (`career/saveSystem.lua:318`).
- [x] Ao carregar: hook `onCareerActive(true, newSave)` depois do mapa carregar (`career/career.lua:237`); `onCareerActive(false)` ao sair (`:326`).
- [x] Pasta do save atual: `career_saveSystem.getCurrentProfile()` retorna `profile, savePath` (`career/saveSystem.lua:224`).
- [x] Gravação segura (arquivo temporário + rename): `career_saveSystem.jsonWriteFileSafe(caminho, tabela, true)` (`:243`).
- [x] Modelo a seguir: `career/modules/logbook.lua:208-237` (lê em `onCareerActive`, grava em `onSaveCurrentProfile`).

RLS (outros nomes):

- [x] Ao salvar: hook `onOverhaulSaveCurrentProfile(savePath, vehiclesThumbnailUpdate, writer)` (`RLS: lua/ge/extensions/overhaul/career/saveSystem.lua:1144`).
- [x] Ao carregar: hook `onOverhaulActive(true, newSave)` (`RLS: .../overhaul/career/career.lua:169`).
- [x] `overhaul_career_saveSystem.getCurrentProfile()` (`RLS: .../career/saveSystem.lua:854`) e `jsonWriteFileSafe` (`:1458`).
- [x] Modelo a seguir: `RLS: .../career/garage/garageManager/ownership.lua:74`.
- [x] Antes de gravar, criar a pasta pelo writer do save: `require('overhaul/lib/save/ensureDir').parentOf(writer, caminho)` (`RLS: lua/ge/extensions/overhaul/lib/save/ensureDir.lua:14`). O `writer` vem no hook; sem ele, `overhaul_career_saveSystem.getSaveWriter()` (`RLS: .../career/saveSystem.lua:299`).
- [x] Ao sair da carreira: `onOverhaulActive(false)` (`RLS: lua/ge/extensions/overhaul/career/start/transitions.lua:711`).
- [x] Relógio: o `onUpdate` da carreira dispara `onOverhaulCareerSimStep(dtSim)` a cada frame com a carreira ativa (`RLS: .../career/career.lua:396-420`). O `dtSim` para quando o jogo pausa. O `fleetSim` soma esse tempo e só simula a cada 2 s.
- [x] Antes de gravar: `onOverhaulSaveCurrentProfileAsyncStart()` roda para todas as extensões antes do `onOverhaulSaveCurrentProfile` (`RLS: .../career/saveSystem.lua:1143-1144`). O saldo é gravado no `onOverhaulSaveCurrentProfile` do `playerAttributes` (`RLS: .../career/economy/playerAttributes.lua:743`), então dinheiro creditado no hook anterior entra no save. O Beamazon paga ali o lucro que ainda estava pendente.
- O `adapter` repassa esses hooks com nomes próprios (`onBeamazonCareerActive`, `onBeamazonBeforeSave`, `onBeamazonSave`, `onBeamazonSimStep`), então os outros módulos não conhecem o RLS.

Onde o mod grava: `<savePath>/career/beamazon.json` nos dois casos. No Linux nativo, o jogo grava os arquivos da pasta do usuário com o nome em minúsculo, então todo arquivo que o mod criar tem nome só em minúsculas. Visto em 2026-10-24: o RLS grava `temp/rls_career/levelcache` mas monta `levelCache` (`RLS: lua/ge/extensions/overhaul/world/levelProxy.lua:14`), e o mapa `rls_west_coast` carrega vazio. O `fleetManager` implementa os dois pares de hooks e o `adapter` diz qual está valendo.

## Entregas (`delivery/`)

- [x] Valor de um volume (`delivery/generator.lua:129`, `getMoneyRewardForParcelItem`):
  `dinheiro = sqrt(slots)/4 + (distância_km)^(1 + sqrt(slots)/100) × (5 + peso^0.9)`
  Exemplo: 4 slots, 5 kg, 2 km ≈ **$19**.
- [x] Multiplicador da organização pela reputação: `deliveryBonus.value` (`delivery/generator.lua:166`).
- [x] Os `moneyMultipler` dos modificadores (`delivery/parcelMods.lua:27`, `:42`, `:58`…) **não são aplicados**: a linha que usaria está comentada (`delivery/generator.lua:135`).
- [x] Ajuste na entrega (`delivery/parcelManager.lua:436`, `getRewardsWithBreakdown`): entrega com prazo paga +10% no horário, cai até 20% se atrasar (`:441-470`); estacionamento preciso dá bônus (`:522`).
- [x] Pagamento: `progress.lua` soma as recompensas e chama `addAttributes(rewardSum, {tags = {"gameplay","reward","delivery"}})` (`delivery/progress.lua:438-443`).
- [x] Tipos de volume vêm de `gameplay/delivery/*.deliveryParcels.json` (lidos em `delivery/generator.lua:181`). Ex.: `warehouses.deliveryParcels.json`, `smallPostParcel` com 1 a 4 slots e 1 a 5 kg.
- [x] Relógio das entregas: `career_modules_delivery_general.time()` (`delivery/general.lua:165`). Se o save tem mais de 1 h, o jogo apaga as cargas pendentes (`:60`).

Para a `fleetEconomy`: usar a mesma fórmula com volumes sorteados desses JSONs, sem gerar ofertas reais no mapa (a frota é abstrata).

RLS (é o que o MVP usa):

- [x] Valor de um volume: `require('overhaul/lib/logistics/calculators').getParcelReward(item, distanciaMetros)` (`RLS: lua/ge/extensions/overhaul/lib/logistics/calculators.lua:299`), com `item = {slots = N, data = {rewardWeight = peso}}`. Retorna `{money = ..., ["logistics-delivery"] = xp, economyMultiplier = ...}`. Já aplica a economia viva do RLS (seção `delivery_parcel`, `:322-336`).
- [x] A fórmula do RLS (`calculators.lua:240`) é outra que a vanilla: ela calibra cada volume por uma meta de pagamento a 4 milhas (6,4 km) por faixa de slots (`RLS: .../logistics/logisticsBalance.lua:31` e `:77`): até 16 slots paga $37,50, até 32 paga $75, até 64 paga $150, até 128 paga $300 (já com o ×1,5 de `:6`). Um volume de 1 slot paga quase o mesmo que um de 16.
- [x] Tipos de volume: `require('overhaul/lib/logistics/templates').getTemplatesByLogisticType('parcel')` (`RLS: lua/ge/extensions/overhaul/lib/logistics/templates.lua:114`), lidos dos mesmos `gameplay/delivery/*.deliveryParcels.json` (`:32-38`). Cada tipo traz `slots` e `weight` como listas e `generationChance`.
- [x] Como o RLS sorteia um volume (modelo do `fleetEconomy.rollTrip`): slots e peso ao acaso das listas, peso com ±10% (`RLS: lua/ge/extensions/overhaul/career/logistics/generator/offers.lua:234-248`).
- [x] Dificuldade (fácil, normal, difícil, hardcore): já vem embutida no `getParcelReward`, nada a espelhar. Cada modo tem um `rewardMultiplier` (`RLS: .../career/economy/difficultyMode.lua:15-18`: fácil ×3, normal ×1, difícil e hardcore ×0,5). O `economyAdjusterPolicy` multiplica a economia de cada seção por ele (`.../career/economy/economyAdjusterPolicy.lua:119` e `:290-305`), e o `calculators` lê a seção `delivery_parcel` (`:324`). O `setHardcoreMultiplier` do `calculators` (`:206`) não tem quem chame. Isso explica o pagamento menor que o do teste fora do jogo: a frota ganha o que o jogador ganharia na mesma dificuldade.

## Garagens e propriedades

Vanilla:

- [x] Limite de veículos: `slotAmount = 20` fixo (`career/modules/inventory.lua:18`); `getNumberOfFreeSlots()` (`:286`), `hasFreeSlot()` (`:294`), `getVehicles()` (`:1136`). O vanilla não tem compra de imóvel.
- [x] Garagens do mapa: `freeroam_facilities.getFacilities(level).garages` (`lua/ge/extensions/freeroam/facilities.lua:78`), `getGarage(id)` (`:130`), `getZonesForFacility` (`:214`); a mais próxima: `career_modules_inventory.getClosestGarage(pos)` (`inventory.lua:36`).
- [x] Menu do computador da garagem (UI da fase 3): o hook `onComputerAddFunctions(menuData, computerFunctions)` (`career/modules/computer.lua:41`) deixa qualquer extensão pôr um botão. Modelo: `career/modules/playerAbstract.lua:14-29`.

RLS:

- [x] Garagens compráveis em `overhaul_career_garage_garageManager` (alias `career_modules_garageManager`): `isPurchasedGarage`, `addPurchasedGarage`, `getOwnedGaragesListingData`, `buyGarage` (`RLS: lua/ge/extensions/overhaul/career/garage/garageManager.lua:206-256`). Assinaturas e retornos: mapear na fase 2, junto com a decisão A/B de localização.
- [x] O RLS também troca `career_modules_inventory` e `career_modules_computer` por versões dele (aliases nos owners `overhaul_career_garage_inventory.json` e `overhaul_career_garage_computer.json`).

## Van robô

- [x] Modelo `simple_traffic` (`content/vehicles/simple_traffic.zip`), parte `simple_traffic_robotvan`.
- [x] Configs: `robotvan_stock`, `robotvan_bamboo`, `robotvan_carefulbot` (`vehicles/simple_traffic/robotvan_*.pc`).
- [x] É `"Type": "PropTraffic"` (`info_robotvan_stock.json`): veículo de tráfego, fora da concessionária, sem `cargoStorage`. Motor elétrico dianteiro (`robotvan_electric_motor_F.jbeam`).
- Para a fase 4: spawnar com `core_vehicles.spawnNewVehicle("simple_traffic", {config = "vehicles/simple_traffic/robotvan_stock.pc"})` (`lua/ge/extensions/core/vehicles.lua:1853`; conferir as opções de `opt` antes de usar).

## RLS (opcional)

- [x] Detecção segura: `extensions.isExtensionLoaded("overhaul_career_career")` (`lua/common/extensions.lua:280`, só checa o global). O RLS carrega as extensões dele 0,25 s depois do `modScript` (`RLS: scripts/rls_career_overhaul/modScript.lua`), então **detecte na hora de usar**, nunca uma vez só no load.
- [x] App do celular: o RLS lê qualquer `gameplay/overhaul/phone/apps/<id>.json` de qualquer mod (comentário em `RLS: ui/ui-vue/mods/rls_career_overhaul/overhaul/modules/career/utils/phoneAppRegistry.js:12-13`). Campos mínimos: `id`, `name`, `route` e um ícone (`icon`/`iconImage`/`iconTile`). Modelo: `RLS: gameplay/overhaul/phone/apps/logistics.json`, que aponta para uma tela Vue em `uiRoutes[].component`. Os arquivos `gameplay/overhaul/{career,ui}/owners/overhaul_phone_apps_*.json` são do registro interno das extensões do RLS; ver na fase 3 se um addon precisa deles.
- [x] App do Beamazon (fase 3): manifesto em `mod/gameplay/overhaul/phone/apps/beamazon.json` e tela em `mod/ui/ui-vue/mods/beamazon/PhoneBeamazon.vue`.
  - O RLS valida o manifesto em `RLS: lua/ge/extensions/overhaul/lib/phone/appDiscovery.lua:43` (o `id` tem que ser igual ao nome do arquivo) e cada rota em `RLS: .../lib/ui/routeValidation.lua`. O componente tem que ficar em `/ui/ui-vue/mods/<mod>/...vue` (`RLS: .../lib/platform/catalog.lua:18`).
  - A tela é um `.vue` comum, compilado pelo jogo em tempo de execução (regras oficiais em `ui/ui-vue/mods/README.md` na pasta do jogo). Ela importa só código do jogo (`vue`, `@/...`), nada do RLS.
  - Chamada ao Lua: `runRaw("expressão Lua")` de `@/bridge/libs/Lua.js` (`ui/ui-vue/src/bridge/libs/Lua.js:149`) devolve o valor da expressão. O atalho `lua.extensions.x.f()` só serve para funções listadas em `LuaFunctionSignatures.js`, então não serve para o mod. Tabela Lua vazia chega no JS como `{}`, não `[]`.
  - Ícone: `icon` é um nome dos ícones do jogo (`ui/ui-vue/src/assets/fonts/bngIcons/svg/`); o Beamazon usa `deliveryTruck`.
  - Nenhum app vem pré-instalado (`PREINSTALLED_APP_IDS = []`, `RLS: .../career/utils/phoneLayoutUtils.js:8`): o jogador instala o Beamazon pela App Store do celular.
- [x] Conta da empresa: livro-caixa com categoria `business` e `payment.pay(..., accountId)` (ver **Dinheiro**).
- [ ] Garagens do Real Estate: assinaturas completas na fase 2.
