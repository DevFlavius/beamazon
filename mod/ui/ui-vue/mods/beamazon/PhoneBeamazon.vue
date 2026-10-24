<template>
  <div class="beamazon-phone">
    <header class="app-header">
      <h1>Beamazon</h1>
      <span>Autonomous delivery fleet</span>
    </header>

    <div v-if="!loaded" class="empty-state">
      <p>Loading…</p>
    </div>

    <div v-else-if="!data.active" class="empty-state">
      <div class="empty-title">Career not active</div>
      <p>Beamazon runs inside an RLS career.</p>
    </div>

    <template v-else>
      <div class="summary">
        <div><span>Vans</span><strong>{{ vans.length }} / {{ data.vanLimit }}</strong></div>
        <div><span>Trips</span><strong>{{ data.totals?.trips ?? 0 }}</strong></div>
        <div><span>Profit</span><strong>{{ money(data.totals?.net ?? 0) }}</strong></div>
      </div>
      <div v-if="data.company?.hq" class="rate">Company HQ · {{ data.company.hqSlots }} fleet slots</div>
      <div v-else-if="data.company" class="rate">Logistics level {{ data.company.hqUnlockLevel }} lets you buy the company HQ ({{ money(data.company.hqPrice) }})</div>
      <div v-if="typeof data.netPerVanHour === 'number'" class="rate">{{ money(data.netPerVanHour) }} profit per van-hour</div>

      <button class="buy-button" type="button" :disabled="buying || atLimit" @click="buyVan">
        <template v-if="atLimit && data.nextVanUnlock">Logistics level {{ data.nextVanUnlock.level }} unlocks a van</template>
        <template v-else-if="atLimit">Van limit reached</template>
        <template v-else>Buy a van · {{ money(data.vanPrice) }}</template>
      </button>
      <div v-if="atLimit && data.nextVanUnlock" class="rate">Your Logistics level: {{ data.logisticsLevel }}</div>
      <div v-if="message" class="message" :class="{ error: messageIsError }">{{ message }}</div>

      <div v-if="vans.length" class="van-list" v-bng-ui-nav-scroll>
        <div v-for="van in vans" :key="van.id" class="van-card">
          <div class="van-top">
            <h2>{{ van.name }}</h2>
            <strong>{{ money(van.net) }}</strong>
          </div>
          <div class="van-status">
            <span v-if="van.onTrip">{{ van.parcels }} parcel{{ van.parcels === 1 ? '' : 's' }} · {{ van.routeKm.toFixed(1) }} km route</span>
            <span v-else>Loading at the depot</span>
            <span>{{ van.trips }} trip{{ van.trips === 1 ? '' : 's' }}</span>
          </div>
          <div class="progress"><div class="progress-fill" :style="{ width: Math.round(van.progress * 100) + '%' }"></div></div>
          <button class="sell-button" type="button" :class="{ confirm: confirmSellId === van.id }" :disabled="selling" @click="sellVan(van)">
            <template v-if="confirmSellId === van.id">Tap again to sell for {{ money(van.sellValue) }}</template>
            <template v-else>Sell · {{ money(van.sellValue) }}</template>
          </button>
        </div>
      </div>

      <div v-else class="empty-state">
        <div class="empty-title">No vans yet</div>
        <p>Buy your first van and it starts delivering on its own. Vans unlock with your Logistics skill.</p>
      </div>
    </template>
  </div>
</template>

<script setup>
import { computed, onMounted, onUnmounted, reactive, ref } from "vue"
import { runRaw } from "@/bridge/libs/Lua.js"
import { vBngUiNavScroll } from "@/common/directives"

const refreshMs = 2000

const data = reactive({ active: false, vanPrice: 0, vanLimit: 0, logisticsLevel: 0, nextVanUnlock: null, company: null, totals: null, netPerVanHour: null, vans: [] })
const loaded = ref(false)
const buying = ref(false)
const message = ref("")
const messageIsError = ref(false)
const selling = ref(false)
// A sale needs a second tap on the same van within confirmMs.
const confirmSellId = ref(null)
const confirmMs = 4000
let confirmTimer = null
let timer = null

// An empty Lua table arrives as {} instead of [].
const vans = computed(() => (Array.isArray(data.vans) ? data.vans : Object.values(data.vans || {})))
const atLimit = computed(() => vans.value.length >= data.vanLimit)

const currency = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" })
function money(value) {
  return currency.format(Number(value) || 0)
}

function apply(payload) {
  if (!payload || typeof payload !== "object") return
  data.active = payload.active === true
  data.vanPrice = payload.vanPrice ?? 0
  data.vanLimit = payload.vanLimit ?? 0
  data.logisticsLevel = payload.logisticsLevel ?? 0
  data.nextVanUnlock = payload.nextVanUnlock ?? null
  data.company = payload.company ?? null
  data.totals = payload.totals ?? null
  data.netPerVanHour = payload.netPerVanHour ?? null
  data.vans = payload.vans ?? []
  loaded.value = true
}

async function refresh() {
  apply(await runRaw("beamazon_phoneApp and beamazon_phoneApp.getData()"))
}

const buyErrors = {
  notEnoughMoney: "Not enough money for a van.",
  careerInactive: "Career not active.",
  vanLimit: "Van limit reached.",
}

async function buyVan() {
  buying.value = true
  try {
    const result = await runRaw("beamazon_phoneApp and beamazon_phoneApp.buyVan()")
    apply(result?.data)
    messageIsError.value = !result?.ok
    message.value = result?.ok ? "A new van joined the fleet." : (buyErrors[result?.reason] || "Could not buy a van.")
  } finally {
    buying.value = false
  }
}

const sellErrors = {
  careerInactive: "Career not active.",
  noVan: "That van is no longer in the fleet.",
}

async function sellVan(van) {
  if (confirmSellId.value !== van.id) {
    confirmSellId.value = van.id
    clearTimeout(confirmTimer)
    confirmTimer = setTimeout(() => (confirmSellId.value = null), confirmMs)
    return
  }
  confirmSellId.value = null
  clearTimeout(confirmTimer)
  selling.value = true
  try {
    const result = await runRaw(`beamazon_phoneApp and beamazon_phoneApp.sellVan(${Number(van.id)})`)
    apply(result?.data)
    messageIsError.value = !result?.ok
    message.value = result?.ok ? `${van.name} sold for ${money(result.value)}.` : (sellErrors[result?.reason] || "Could not sell the van.")
  } finally {
    selling.value = false
  }
}

onMounted(() => {
  refresh()
  timer = setInterval(refresh, refreshMs)
})

onUnmounted(() => {
  clearInterval(timer)
  clearTimeout(confirmTimer)
})
</script>

<style scoped lang="scss">
.beamazon-phone {
  height: 100%;
  min-height: 0;
  color: #fff;
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 46px 10px 12px;
  overflow: hidden;
  box-sizing: border-box;
  background:
    linear-gradient(180deg, rgba(217, 119, 6, 0.45), rgba(12, 11, 10, 0.96) 40%),
    #12100e;
}

.app-header {
  display: grid;
  gap: 2px;
  padding: 0 2px;

  h1 {
    margin: 0;
    font-size: 1.3rem;
    font-weight: 800;
  }

  span {
    color: #fcd9a8;
    font-size: 0.8rem;
  }
}

.summary {
  display: grid;
  grid-template-columns: 1fr 1fr 1.4fr;
  gap: 6px;

  > div {
    display: grid;
    gap: 2px;
    padding: 7px 8px;
    border-radius: 6px;
    background: rgba(255, 255, 255, 0.08);
  }

  span {
    color: #d8d8d8;
    font-size: 0.72rem;
    text-transform: uppercase;
  }

  strong {
    font-size: 0.95rem;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
}

.rate {
  color: #fcd9a8;
  font-size: 0.78rem;
  padding: 0 2px;
}

.buy-button {
  flex: 0 0 auto;
  min-height: 38px;
  border: 0;
  border-radius: 8px;
  background: #d97706;
  color: #fff;
  font: inherit;
  font-weight: 700;

  &:disabled {
    opacity: 0.6;
  }
}

.message {
  color: #bfe5b9;
  font-size: 0.82rem;
  padding: 0 2px;

  &.error {
    color: #ffb4a8;
  }
}

.van-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
  min-height: 0;
  overflow-y: auto;
  padding-right: 2px;
}

.van-card {
  flex: 0 0 auto;
  display: grid;
  gap: 5px;
  padding: 9px 10px;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.08);
  border: 1px solid rgba(252, 217, 168, 0.22);
}

.van-top {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 8px;

  h2 {
    margin: 0;
    font-size: 1rem;
  }

  strong {
    color: #bfe5b9;
    font-size: 0.9rem;
  }
}

.van-status {
  display: flex;
  justify-content: space-between;
  gap: 8px;
  color: #d8d8d8;
  font-size: 0.8rem;
}

.progress {
  height: 4px;
  border-radius: 2px;
  background: rgba(255, 255, 255, 0.12);
  overflow: hidden;
}

.sell-button {
  justify-self: end;
  border: 1px solid rgba(252, 217, 168, 0.35);
  border-radius: 6px;
  background: transparent;
  color: #fcd9a8;
  font: inherit;
  font-size: 0.75rem;
  padding: 3px 8px;

  &.confirm {
    background: #b45309;
    border-color: #b45309;
    color: #fff;
  }

  &:disabled {
    opacity: 0.6;
  }
}

.progress-fill {
  height: 100%;
  background: #f59e0b;
  transition: width 0.5s linear;
}

.empty-state {
  flex: 1 1 auto;
  display: grid;
  place-content: center;
  gap: 7px;
  text-align: center;

  p {
    margin: 0;
    color: #d5d5d5;
    font-size: 0.9rem;
  }
}

.empty-title {
  font-size: 1.12rem;
  font-weight: 700;
}
</style>
