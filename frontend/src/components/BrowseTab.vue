<script lang="ts" setup>
import { computed, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import {
  browseDictionary,
  browseItemDetail,
  browseLetters,
  type BrowseItem,
  type BrowseItemDetail,
  type BrowseLetter,
} from '../lib/browseClient'
import LetterJumpSidebar from './LetterJumpSidebar.vue'

const data = reactive({
  items: [] as BrowseItem[],
  letters: [] as BrowseLetter[],
  letter: '',
  limit: 50,
  nextOffset: 0,
  hasMore: false,
  loading: false,
  loadingMore: false,
  error: '',
  selectedWordID: 0,
  selectedItemDetail: null as BrowseItemDetail | null,
  detailLoading: false,
  detailError: '',
})

const loadMoreSentinel = ref<HTMLElement | null>(null)
const canUseIntersectionObserver = typeof window !== 'undefined' && 'IntersectionObserver' in window
let browseController: AbortController | null = null
let browseRequestToken = 0
let detailController: AbortController | null = null
let detailRequestToken = 0
let loadMoreObserver: IntersectionObserver | null = null

function appendUniqueItems(existing: BrowseItem[], incoming: BrowseItem[]): BrowseItem[] {
  if (incoming.length === 0) {
    return existing
  }

  const seen = new Set(existing.map((item) => item.WordID))
  const appended = existing.slice()

  for (const item of incoming) {
    if (seen.has(item.WordID)) {
      continue
    }

    appended.push(item)
    seen.add(item.WordID)
  }

  return appended
}

async function loadLetters() {
  try {
    data.letters = await browseLetters()
  } catch (err) {
    console.error('Browse letters failed:', err)
  }
}

function resetSelectedItem() {
  data.selectedWordID = 0
  data.selectedItemDetail = null
  data.detailError = ''
  data.detailLoading = false

  if (detailController) {
    detailController.abort()
    detailController = null
  }
}

async function loadBrowse(reset = true) {
  if (reset) {
    if (data.loading) {
      return
    }
    data.loadingMore = false
    resetSelectedItem()
  } else if (data.loading || data.loadingMore || !data.hasMore) {
    return
  }

  data.error = ''
  const offset = reset ? 0 : data.nextOffset
  const requestToken = ++browseRequestToken

  if (browseController) {
    browseController.abort()
  }

  browseController = new AbortController()

  if (reset) {
    data.loading = true
  } else {
    data.loadingMore = true
  }

  try {
    const page = await browseDictionary(data.letter, data.limit, offset, browseController.signal)
    if (requestToken !== browseRequestToken) {
      return
    }

    data.items = reset ? page.items : appendUniqueItems(data.items, page.items)
    data.nextOffset = page.pagination.nextOffset
    data.hasMore = page.pagination.hasMore
  } catch (err) {
    if ((err as DOMException)?.name === 'AbortError') {
      return
    }

    if (requestToken !== browseRequestToken) {
      return
    }

    console.error('Browse failed:', err)
    data.error = 'Browse is unavailable right now.'
    if (reset) {
      data.items = []
      data.nextOffset = 0
      data.hasMore = false
    }
  } finally {
    if (requestToken !== browseRequestToken) {
      return
    }

    browseController = null
    if (reset) {
      data.loading = false
      data.loadingMore = false
    } else {
      data.loadingMore = false
    }
  }
}

async function loadBrowseItemDetail(wordID: number) {
  if (data.selectedWordID === wordID && data.selectedItemDetail && !data.detailError) {
    return
  }

  data.selectedWordID = wordID
  data.selectedItemDetail = null
  data.detailError = ''
  data.detailLoading = true

  if (detailController) {
    detailController.abort()
  }

  detailController = new AbortController()
  const requestToken = ++detailRequestToken

  try {
    const detail = await browseItemDetail(wordID, detailController.signal)
    if (requestToken !== detailRequestToken) {
      return
    }

    data.selectedItemDetail = detail
  } catch (err) {
    if ((err as DOMException)?.name === 'AbortError') {
      return
    }

    if (requestToken !== detailRequestToken) {
      return
    }

    console.error('Browse item detail failed:', err)
    data.detailError = 'Unable to load entry details.'
  } finally {
    if (requestToken !== detailRequestToken) {
      return
    }

    detailController = null
    data.detailLoading = false
  }
}

const letterCounts = computed<Record<string, number>>(() => {
  return data.letters.reduce<Record<string, number>>((counts, item) => {
    counts[item.letter] = item.count
    return counts
  }, {})
})

function onLetterJump(letter: string) {
  if (data.letter === letter && data.items.length > 0) {
    return
  }

  data.letter = letter
  void loadBrowse(true)
}

function setupLoadMoreObserver() {
  if (!canUseIntersectionObserver || !loadMoreSentinel.value) {
    return
  }

  loadMoreObserver = new IntersectionObserver(
    (entries) => {
      if (entries.some((entry) => entry.isIntersecting)) {
        void loadBrowse(false)
      }
    },
    { rootMargin: '180px 0px' },
  )

  loadMoreObserver.observe(loadMoreSentinel.value)
}

onMounted(() => {
  setupLoadMoreObserver()
  void Promise.all([loadLetters(), loadBrowse(true)])
})

watch(loadMoreSentinel, (element) => {
  if (!canUseIntersectionObserver) {
    return
  }

  if (loadMoreObserver) {
    loadMoreObserver.disconnect()
    loadMoreObserver = null
  }

  if (element) {
    setupLoadMoreObserver()
  }
})

onBeforeUnmount(() => {
  if (browseController) {
    browseController.abort()
  }

  if (detailController) {
    detailController.abort()
  }

  if (loadMoreObserver) {
    loadMoreObserver.disconnect()
    loadMoreObserver = null
  }
})
</script>

<template>
  <div class="browse-layout">
    <section>
      <form class="controls" @submit.prevent="loadBrowse(true)">
        <input v-model.number="data.limit" type="number" class="input short" min="1" max="100" />
        <button class="btn" type="submit">Refresh</button>
      </form>
    </section>

    <section class="results">
      <div v-if="data.error">{{ data.error }}</div>
      <div v-else-if="data.loading">Loading...</div>
      <div v-else-if="data.items.length === 0">No entries</div>
      <div v-else>
        <div v-for="word in data.items" :key="word.WordID" class="card browse-item" :class="{ selected: data.selectedWordID === word.WordID }">
          <button class="browse-item-trigger" type="button" @click="loadBrowseItemDetail(word.WordID)">
            <h3>{{ word.Balochi }} <small>({{ word.Latin }})</small></h3>
            <p><strong>Normalized:</strong> {{ word.NormalizedLatin }}</p>
          </button>

          <div v-if="data.selectedWordID === word.WordID" class="inline-detail">
            <p v-if="data.detailLoading">Loading entry details...</p>
            <p v-else-if="data.detailError">{{ data.detailError }}</p>
            <template v-else-if="data.selectedItemDetail">
              <ul v-if="data.selectedItemDetail.Definitions.length > 0">
                <li v-for="(def, index) in data.selectedItemDetail.Definitions" :key="index">
                  <em>{{ def.PartOfSpeech }}:</em> {{ def.Text }}
                </li>
              </ul>
              <p v-else>No definitions</p>
            </template>
          </div>
        </div>
        <div ref="loadMoreSentinel" class="load-more-sentinel" aria-hidden="true"></div>
        <button v-if="data.hasMore" class="btn load-more" type="button" :disabled="data.loadingMore" @click="loadBrowse(false)">
          {{ data.loadingMore ? 'Loading...' : 'Load more' }}
        </button>
      </div>
    </section>
    <LetterJumpSidebar :active-letter="data.letter" :letter-counts="letterCounts" @jump="onLetterJump" />
  </div>
</template>

<style scoped>
.browse-layout {
  padding-right: 4rem;
}

.controls {
  display: flex;
  align-items: center;
  gap: 1rem;
  margin-bottom: 2rem;
  flex-wrap: wrap;
}

.input {
  height: 35px;
  padding: 0 10px;
  border-radius: 5px;
  border: 1px solid #444;
  background-color: #1e1e1e;
  color: #ddd;
}

.input:focus {
  outline: none;
  border-color: #66aaff;
}

.input.short {
  width: 80px;
}

.input.medium {
  width: 180px;
}

.btn {
  padding: 0 20px;
  height: 35px;
  border: none;
  border-radius: 5px;
  background: #3366cc;
  color: white;
  font-weight: bold;
  cursor: pointer;
}

.btn:hover {
  background: #5588dd;
}

.btn:disabled {
  opacity: 0.7;
  cursor: default;
}

.card {
  background-color: #393e46;
  color: #f0f0f0;
  padding: 1rem;
  border-radius: 8px;
  box-shadow: 0 0 6px rgba(0, 0, 0, 0.4);
  margin-bottom: 1rem;
}

.results h3 {
  margin: 0 0 0.25rem 0;
}

.browse-item {
  width: 100%;
  border: 1px solid transparent;
  text-align: left;
}

.browse-item-trigger {
  width: 100%;
  text-align: left;
  background: transparent;
  border: 0;
  color: inherit;
  cursor: pointer;
  padding: 0;
}

.browse-item.selected {
  border-color: #66aaff;
}

.inline-detail {
  margin-top: 0.75rem;
  padding-top: 0.75rem;
  border-top: 1px solid #4e5762;
}

.inline-detail ul {
  margin: 0.25rem 0 0 1rem;
  padding: 0;
  list-style-type: disc;
}

.inline-detail em {
  color: #a0cfff;
}

.load-more {
  margin-top: 0.5rem;
}

.load-more-sentinel {
  height: 1px;
}
</style>
