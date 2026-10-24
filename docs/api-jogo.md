# API do jogo usada pelo mod

Funções reais da carreira (BeamNG.drive **0.40.3**) que o `adapter.lua` chama. Cada item traz o caminho e a linha no código do jogo. Quando o jogo atualizar, revise esta lista primeiro.

Preenchido na fase 0. Nada aqui foi verificado ainda.

## Entregas (`lua/ge/extensions/career/modules/delivery/`)

- [ ] Como as ofertas são geradas (`generator.lua`)
- [ ] Como o valor da entrega é calculado
- [ ] Como uma entrega concluída paga o jogador (`general.lua`, `progress.lua`)

## Dinheiro

- [ ] Crédito e débito no saldo (`payment.lua`, `playerAttributes.lua`)

## Save / load

- [ ] Hook chamado ao salvar o perfil da carreira
- [ ] Hook chamado ao carregar o perfil
- [ ] Onde o mod grava o próprio estado

## Garagens e propriedades

- [ ] Slots de garagem e propriedades do jogador (`inventory.lua`)

## Van robô

- [ ] Nome interno do modelo e as configs disponíveis

## RLS (opcional)

- [ ] Detecção segura do RLS
- [ ] Registro de um app no celular
- [ ] Conta da empresa e garagens do Real Estate
