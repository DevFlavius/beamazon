<template>
  <div class="beamazon-phone">
    <header class="app-header">
      <h1>Beamazon</h1>
      <span>{{ data.company?.hq ? `Delivery company · level ${data.company.level?.level ?? 1}` : "Autonomous delivery fleet" }}</span>
    </header>

    <div v-if="!loaded" class="empty-state">
      <p>Loading…</p>
    </div>

    <div v-else-if="!data.active" class="empty-state">
      <div class="empty-title">Career not active</div>
      <p>Beamazon runs inside an RLS career.</p>
    </div>

    <template v-else>
      <nav class="tabs">
        <button v-for="t in tabs" :key="t.id" type="button" :class="{ active: tab === t.id }" @click="tab = t.id">{{ t.label }}</button>
      </nav>

      <div v-if="message" class="message" :class="{ error: messageIsError }">{{ message }}</div>

      <!-- Fleet -->
      <template v-if="tab === 'fleet'">
        <div class="summary">
          <div><span>Vehicles</span><strong>{{ vans.length }} / {{ data.vanLimit }}</strong></div>
          <div><span>Trips</span><strong>{{ data.totals?.trips ?? 0 }}</strong></div>
          <div><span>Profit</span><strong>{{ money(data.totals?.net ?? 0) }}</strong></div>
        </div>
        <button v-if="data.serviceAllCost > 0" class="service-all-button" type="button" :disabled="busy" @click="act('serviceAll', 'All vehicles serviced.')">
          Service all · {{ money(data.serviceAllCost) }}
        </button>
        <div v-if="!data.company?.hq && data.company" class="rate">Logistics level {{ data.company.hqUnlockLevel }} lets you buy the company HQ ({{ money(data.company.hqPrice) }})</div>
        <div v-if="typeof data.netPerVanHour === 'number'" class="rate">{{ money(data.netPerVanHour) }} profit per van-hour</div>

        <div class="buy-row">
          <button class="buy-button" type="button" :disabled="busy || atLimit" @click="act('buyVan', 'A new van joined the fleet.')">
            <template v-if="atLimit && data.nextVanUnlock">Logistics level {{ data.nextVanUnlock.level }} unlocks a van</template>
            <template v-else-if="atLimit">Fleet is full</template>
            <template v-else>Van · {{ money(data.vanPrice) }}</template>
          </button>
          <button v-if="data.company?.hq" class="buy-button truck" type="button" :disabled="busy || atLimit" @click="act('buyTruck', 'A new truck joined the fleet. It needs a driver.')">
            Truck · {{ money(data.company.truckPrice) }}
          </button>
        </div>
        <div v-if="atLimit && data.nextVanUnlock" class="rate">Your Logistics level: {{ data.logisticsLevel }}</div>
        <button v-if="data.company?.hqOnThisMap && !data.company?.hq" class="route-button" type="button" @click="act('routeToHq', 'Route set: follow the GPS to the Beamazon HQ.', 'Get in a vehicle to set the route.')">Route to the Beamazon HQ</button>

        <div v-if="vans.length" class="list" v-bng-ui-nav-scroll>
          <div v-for="van in vans" :key="van.id" class="card" :class="{ parked: van.kind === 'truck' && !van.driver }">
            <div class="card-top">
              <h2>{{ van.name }}</h2>
              <strong>{{ money(van.net) }}</strong>
            </div>
            <div class="card-status">
              <span v-if="van.brokenMinutes > 0" class="status-broken">Broken down · {{ van.brokenMinutes }} min</span>
              <span v-else-if="van.kind === 'truck' && !van.driver">Parked · no driver</span>
              <span v-else-if="van.onTrip">{{ van.parcels }} parcel{{ van.parcels === 1 ? '' : 's' }} · {{ van.routeKm.toFixed(1) }} km<template v-if="van.driver"> · {{ van.driver }}</template></span>
              <span v-else>Loading at the depot</span>
              <span>{{ van.trips }} trip{{ van.trips === 1 ? '' : 's' }}</span>
            </div>
            <div class="progress"><div class="progress-fill" :style="{ width: Math.round(van.progress * 100) + '%' }"></div></div>
            <div class="condition-bar-wrap">
              <div class="condition-label">Condition {{ van.condition }}%</div>
              <div class="condition-bar"><div class="condition-fill" :class="conditionClass(van.condition)" :style="{ width: van.condition + '%' }"></div></div>
            </div>
            <div class="card-buttons">
              <button v-if="van.condition < 100" class="small-button service" type="button" :disabled="busy" @click="act(`serviceVan(${Number(van.id)})`, `${van.name} serviced.`)">
                Service {{ money(van.serviceCost) }}
              </button>
              <button class="small-button" type="button" :class="{ confirm: confirmId === 'sell' + van.id }" :disabled="busy" @click="confirm('sell' + van.id, () => sellVan(van))">
                <template v-if="confirmId === 'sell' + van.id">Tap again to sell for {{ money(van.sellValue) }}</template>
                <template v-else>Sell · {{ money(van.sellValue) }}</template>
              </button>
            </div>
          </div>
        </div>

        <div v-else class="empty-state">
          <div class="empty-title">No vans yet</div>
          <p>Buy your first van and it starts delivering on its own. Vans unlock with your Logistics skill.</p>
        </div>
      </template>

      <!-- Company -->
      <div v-else-if="tab === 'company' && data.company?.hq" class="list" v-bng-ui-nav-scroll>
        <div class="card">
          <div class="card-top">
            <h2>Level {{ company.level.level }}</h2>
            <strong>{{ company.xp }} XP to spend</strong>
          </div>
          <div class="progress"><div class="progress-fill" :style="{ width: levelProgress + '%' }"></div></div>
          <div class="card-status">
            <span>{{ Math.floor(company.level.xpEarned) }} XP earned</span>
            <span v-if="company.level.next">Next level at {{ company.level.next }}</span>
            <span v-else>Top level</span>
          </div>
          <div class="hint">The fleet earns company XP from its profit. Spend it with money on Upgrades.</div>
        </div>

        <div class="card">
          <div class="card-top">
            <h2>Drivers</h2>
            <strong>{{ drivers.length }} / {{ company.driverSlots }}</strong>
          </div>
          <div class="hint">Each truck needs a driver. A driver earns {{ Math.round(company.driverWageShare * 100) }}% of each truck trip. Trucks without one stay parked, at no cost.</div>
          <div v-for="driver in drivers" :key="driver.id" class="row">
            <span>{{ driver.name }} · {{ driver.trips }} trip{{ driver.trips === 1 ? '' : 's' }} · paid {{ money(driver.earned) }}</span>
            <button class="small-button" type="button" :class="{ confirm: confirmId === 'fire' + driver.id }" :disabled="busy" @click="confirm('fire' + driver.id, () => act(`fireDriver(${Number(driver.id)})`, `${driver.name} left the company.`))">
              {{ confirmId === 'fire' + driver.id ? 'Tap again' : 'Fire' }}
            </button>
          </div>
          <button class="buy-button" type="button" :disabled="busy || drivers.length >= company.driverSlots" @click="act('hireDriver', 'A new driver joined the company.')">
            {{ drivers.length >= company.driverSlots ? 'Hire Drivers upgrade adds a slot' : 'Hire a driver' }}
          </button>
        </div>

        <div class="card">
          <div class="card-top">
            <h2>Trucks</h2>
            <strong>{{ company.trucks }}</strong>
          </div>
          <div class="card-status">
            <span v-if="typeof company.netPerTruckHour === 'number'">{{ money(company.netPerTruckHour) }} profit per truck-hour, driver paid</span>
            <span v-else>Trucks carry more and drive farther: slower trips that pay much more.</span>
          </div>
        </div>

        <div class="card">
          <div class="card-top">
            <h2>Branches</h2>
          </div>
          <div v-for="branch in branches" :key="branch.id" class="row">
            <span>{{ branch.name }} · +{{ branch.slots }} slots · {{ branch.owned ? 'Owned' : `${money(branch.price)} · company level ${branch.companyLevel}` }}</span>
            <button v-if="branch.onThisMap" class="small-button" type="button" :disabled="busy" @click="act(`routeToSite('${safeId(branch.siteId)}')`, 'Route set: follow the GPS to the branch.', 'Get in a vehicle to set the route.')">
              Route
            </button>
          </div>
          <div class="hint">Buy a branch at its spot on the map.</div>
        </div>

        <button v-if="company.hqOnThisMap" class="route-button" type="button" @click="act('routeToHq', 'Route set: follow the GPS to the Beamazon HQ.', 'Get in a vehicle to set the route.')">Route to the Beamazon HQ</button>
      </div>

      <!-- Upgrades -->
      <div v-else-if="tab === 'upgrades' && data.company?.hq" class="list" v-bng-ui-nav-scroll>
        <div class="rate">{{ company.xp }} company XP to spend</div>
        <template v-for="group in upgradeGroups" :key="group.name">
          <div class="group-title">{{ group.name }}</div>
          <div v-for="node in group.nodes" :key="node.id" class="card" :class="{ maxed: node.level >= node.maxLevel }">
            <div class="card-top">
              <h2>{{ node.title }}</h2>
              <strong>{{ node.level }} / {{ node.maxLevel }}</strong>
            </div>
            <div class="hint">{{ node.description }}</div>
            <div v-if="node.reason === 'locked'" class="hint locked">Needs {{ node.requires.map((r) => `${r.title} ${r.level}`).join(', ') }}</div>
            <button v-if="node.level < node.maxLevel" class="small-button buy" type="button" :disabled="busy || !node.canBuy" @click="act(`buyUpgrade('${safeId(node.id)}')`, `${node.title} upgraded.`)">
              {{ money(node.price) }} · {{ node.xpCost }} XP<template v-if="node.reason === 'notEnoughXp'"> · not enough XP</template>
            </button>
            <div v-else class="hint">Maxed</div>
          </div>
        </template>
      </div>

      <!-- Finances -->
      <template v-else-if="tab === 'finances'">
        <div v-if="hasDeliveries" class="list" v-bng-ui-nav-scroll>
          <div class="card">
            <div class="card-top">
              <h2>Last 24 h</h2>
              <strong>{{ money(historyTotals.net) }}</strong>
            </div>
            <div class="row"><span>Revenue</span><span>{{ money(historyTotals.revenue) }}</span></div>
            <div class="row"><span>Energy</span><span>{{ money(historyTotals.energy) }}</span></div>
            <div class="row"><span>Wear</span><span>{{ money(historyTotals.wear) }}</span></div>
            <div class="row"><span>Commission</span><span>{{ money(historyTotals.commission) }}</span></div>
            <div class="row"><span>Driver wages</span><span>{{ money(historyTotals.wages) }}</span></div>
            <div class="row"><span>Repairs and service</span><span>{{ money(historyTotals.repairs) }}</span></div>
            <div class="row"><span>Purchases and sales</span><span>{{ money(historyTotals.purchases) }}</span></div>
            <div class="row"><strong>Net</strong><strong>{{ money(historyTotals.net) }}</strong></div>
          </div>

          <div class="card">
            <div class="card-top">
              <h2>Hourly net</h2>
            </div>
            <div class="chart-container" :class="{ 'has-neg': hasNegative }">
              <div v-for="bucket in history" :key="bucket.hour" class="chart-col" :title="chartTooltip(bucket)">
                <div class="chart-pos">
                  <div class="chart-bar positive" :style="{ height: barHeight(bucket.net, true) }"></div>
                </div>
                <div class="chart-axis"></div>
                <div v-if="hasNegative" class="chart-neg">
                  <div class="chart-bar negative" :style="{ height: barHeight(bucket.net, false) }"></div>
                </div>
                <span class="chart-label">{{ formatHour(bucket.hour) }}</span>
              </div>
            </div>
          </div>
        </div>

        <div v-else class="empty-state">
          <p>No deliveries yet.</p>
        </div>
      </template>
    </template>
  </div>
</template>

<script setup>
import { computed, onMounted, onUnmounted, reactive, ref } from "vue"
import { runRaw } from "@/bridge/libs/Lua.js"
import { vBngUiNavScroll } from "@/common/directives"

const refreshMs = 2000

const data = reactive({ active: false, vanPrice: 0, vanLimit: 0, logisticsLevel: 0, nextVanUnlock: null, company: null, totals: null, netPerVanHour: null, vans: [], serviceAllCost: 0, history: [], historyTotals: null })
const loaded = ref(false)
const busy = ref(false)
const message = ref("")
const messageIsError = ref(false)
const tab = ref("fleet")
const tabs = computed(() => {
  if (data.company?.hq) {
    return [
      { id: "fleet", label: "Fleet" },
      { id: "company", label: "Company" },
      { id: "upgrades", label: "Upgrades" },
      { id: "finances", label: "Finances" },
    ]
  }
  return [
    { id: "fleet", label: "Fleet" },
    { id: "finances", label: "Finances" },
  ]
})
// A sale or a firing needs a second tap on the same button within confirmMs.
const confirmId = ref(null)
const confirmMs = 4000
let confirmTimer = null
let timer = null

// An empty Lua table arrives as {} instead of [].
const asList = (value) => (Array.isArray(value) ? value : Object.values(value || {}))
const vans = computed(() => asList(data.vans))
const atLimit = computed(() => vans.value.length >= data.vanLimit)
const company = computed(() => data.company || {})
const drivers = computed(() => asList(data.company?.drivers))
const branches = computed(() => asList(data.company?.branches))
const history = computed(() => asList(data.history))
const historyTotals = computed(() => data.historyTotals || {
  trips: 0,
  revenue: 0,
  energy: 0,
  wear: 0,
  commission: 0,
  wages: 0,
  purchases: 0,
  repairs: 0,
  net: 0,
})

function conditionClass(condition) {
  const val = Number(condition) || 0
  if (val >= 70) return "good"
  if (val >= 40) return "warn"
  return "bad"
}
const hasDeliveries = computed(() => history.value.length > 0 && (data.historyTotals?.trips ?? 0) > 0)
const hasNegative = computed(() => history.value.some((b) => (Number(b.net) || 0) < 0))

const maxNet = computed(() => {
  let m = 0
  for (const b of history.value) {
    const val = Math.abs(Number(b.net) || 0)
    if (val > m) m = val
  }
  return m > 0 ? m : 1
})

function barHeight(net, isPositive) {
  const val = Number(net) || 0
  if (isPositive) {
    if (val <= 0) return "0%"
    return Math.max(5, Math.round((val / maxNet.value) * 100)) + "%"
  } else {
    if (val >= 0) return "0%"
    return Math.max(5, Math.round((-val / maxNet.value) * 100)) + "%"
  }
}

function formatHour(hour) {
  return `${new Date((Number(hour) || 0) * 1000).getHours()}h`
}

function chartTooltip(bucket) {
  return `${formatHour(bucket.hour)}: ${money(bucket.net)}`
}
const levelProgress = computed(() => {
  const level = data.company?.level
  if (!level || !level.next) return 100
  return Math.min(100, Math.max(0, Math.round(((level.xpEarned - level.current) / (level.next - level.current)) * 100)))
})
const upgradeGroups = computed(() => {
  const groups = []
  for (const node of asList(data.company?.tree)) {
    let group = groups.find((g) => g.name === node.group)
    if (!group) groups.push((group = { name: node.group, nodes: [] }))
    group.nodes.push({ ...node, requires: asList(node.requires) })
  }
  return groups
})

const currency = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", maximumFractionDigits: 0 })
function money(value) {
  return currency.format(Number(value) || 0)
}

// Upgrade ids come from the Lua tree; keep only letters before putting one in a Lua call.
function safeId(id) {
  return String(id).replace(/[^A-Za-z]/g, "")
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
  data.serviceAllCost = payload.serviceAllCost ?? 0
  data.history = payload.history ?? []
  data.historyTotals = payload.historyTotals ?? null
  if (!data.company?.hq && tab.value !== "fleet" && tab.value !== "finances") {
    tab.value = "fleet"
  }
  loaded.value = true
}

async function refresh() {
  apply(await runRaw("beamazon_phoneApp and beamazon_phoneApp.getData()"))
}

const errors = {
  notEnoughMoney: "Not enough money.",
  careerInactive: "Career not active.",
  vanLimit: "The fleet is full.",
  noCompany: "You need the company HQ.",
  noVan: "Vehicle not found.",
  alreadyNew: "Already in perfect condition.",
  driverSlots: "No free driver slot: buy the Hire Drivers upgrade.",
  noDriver: "That driver already left.",
  notEnoughXp: "Not enough company XP.",
  locked: "Buy the upgrades it needs first.",
  maxLevel: "Already at the top level.",
  noRoute: "Get in a vehicle to set the route.",
}

// Runs beamazon_phoneApp.<call> (a function name, or a call with its arguments) and shows the outcome.
async function act(call, okText, failText) {
  busy.value = true
  try {
    const expression = call.includes("(") ? call : `${call}()`
    const result = await runRaw(`beamazon_phoneApp and beamazon_phoneApp.${expression}`)
    apply(result?.data)
    messageIsError.value = !result?.ok
    message.value = result?.ok ? okText : failText || errors[result?.reason] || "That didn't work."
  } finally {
    busy.value = false
  }
}

function confirm(id, action) {
  if (confirmId.value !== id) {
    confirmId.value = id
    clearTimeout(confirmTimer)
    confirmTimer = setTimeout(() => (confirmId.value = null), confirmMs)
    return
  }
  confirmId.value = null
  clearTimeout(confirmTimer)
  action()
}

async function sellVan(van) {
  busy.value = true
  try {
    const result = await runRaw(`beamazon_phoneApp and beamazon_phoneApp.sellVan(${Number(van.id)})`)
    apply(result?.data)
    messageIsError.value = !result?.ok
    message.value = result?.ok ? `${van.name} sold for ${money(result.value)}.` : errors[result?.reason] || "Could not sell it."
  } finally {
    busy.value = false
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

.tabs {
  display: flex;
  gap: 4px;

  button {
    flex: 1 1 0;
    min-height: 30px;
    border: 0;
    border-radius: 6px;
    background: rgba(255, 255, 255, 0.08);
    color: #d8d8d8;
    font: inherit;
    font-size: 0.82rem;

    &.active {
      background: #d97706;
      color: #fff;
      font-weight: 700;
    }
  }
}

.buy-row {
  display: flex;
  gap: 6px;

  .buy-button {
    flex: 1 1 0;
  }
}

.row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 6px;
  color: #d8d8d8;
  font-size: 0.8rem;
}

.hint {
  color: #cfc6bb;
  font-size: 0.76rem;

  &.locked {
    color: #ffb4a8;
  }
}

.group-title {
  color: #fcd9a8;
  font-size: 0.72rem;
  font-weight: 700;
  text-transform: uppercase;
  padding: 4px 2px 0;
}

.card.parked,
.card.maxed {
  opacity: 0.7;
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

  &.truck {
    background: #92400e;
  }

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

.list {
  display: flex;
  flex-direction: column;
  gap: 8px;
  min-height: 0;
  overflow-y: auto;
  padding-right: 2px;
}

.card {
  flex: 0 0 auto;
  display: grid;
  gap: 5px;
  padding: 9px 10px;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.08);
  border: 1px solid rgba(252, 217, 168, 0.22);
}

.card-top {
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

.card-status {
  display: flex;
  justify-content: space-between;
  gap: 8px;
  color: #d8d8d8;
  font-size: 0.8rem;
}

.status-broken {
  color: #ef4444;
  font-weight: 700;
}

.condition-bar-wrap {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.condition-label {
  font-size: 0.72rem;
  color: #d8d8d8;
}

.condition-bar {
  height: 3px;
  border-radius: 2px;
  background: rgba(255, 255, 255, 0.12);
  overflow: hidden;
}

.condition-fill {
  height: 100%;
  transition: width 0.3s ease;

  &.good {
    background: #22c55e;
  }

  &.warn {
    background: #f59e0b;
  }

  &.bad {
    background: #ef4444;
  }
}

.card-buttons {
  display: flex;
  justify-content: flex-end;
  gap: 6px;
}

.progress {
  height: 4px;
  border-radius: 2px;
  background: rgba(255, 255, 255, 0.12);
  overflow: hidden;
}

.service-all-button {
  flex: 0 0 auto;
  min-height: 28px;
  border: 1px solid rgba(34, 197, 94, 0.5);
  border-radius: 6px;
  background: rgba(34, 197, 94, 0.18);
  color: #bfe5b9;
  font: inherit;
  font-size: 0.8rem;
  font-weight: 600;

  &:disabled {
    opacity: 0.6;
  }
}

.route-button {
  flex: 0 0 auto;
  min-height: 30px;
  border: 1px solid rgba(252, 217, 168, 0.45);
  border-radius: 8px;
  background: transparent;
  color: #fcd9a8;
  font: inherit;
  font-size: 0.82rem;
}

.small-button {
  justify-self: end;
  border: 1px solid rgba(252, 217, 168, 0.35);
  border-radius: 6px;
  background: transparent;
  color: #fcd9a8;
  font: inherit;
  font-size: 0.75rem;
  padding: 3px 8px;

  &.service {
    background: rgba(34, 197, 94, 0.2);
    border-color: rgba(34, 197, 94, 0.5);
    color: #bfe5b9;
  }

  &.buy {
    justify-self: stretch;
    background: rgba(217, 119, 6, 0.25);
    color: #fff;
  }

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

.chart-container {
  display: flex;
  gap: 4px;
  min-height: 100px;
  padding: 6px 0 2px;
  overflow-x: auto;
  align-items: stretch;

  &:not(.has-neg) .chart-pos {
    height: 75px;
  }
}

.chart-col {
  flex: 1 0 16px;
  display: flex;
  flex-direction: column;
  align-items: center;
  min-width: 0;
}

.chart-pos {
  height: 55px;
  width: 100%;
  display: flex;
  align-items: flex-end;
  justify-content: center;
}

.chart-axis {
  width: 100%;
  height: 1px;
  background: rgba(255, 255, 255, 0.2);
}

.chart-neg {
  height: 35px;
  width: 100%;
  display: flex;
  align-items: flex-start;
  justify-content: center;
}

.chart-bar {
  width: 8px;
  border-radius: 2px;

  &.positive {
    background: #22c55e;
  }

  &.negative {
    background: #ef4444;
  }
}

.chart-label {
  margin-top: 4px;
  font-size: 0.68rem;
  color: #cfc6bb;
  white-space: nowrap;
}
</style>
