<script lang="ts" setup>
import { reactive } from 'vue'
import { Search } from '../../wailsjs/go/main/App'

const data = reactive({
  keyword: '',
  searchMethod: 'balochi',
  limit: 100,
  results: [] as any[]
})

async function search() {
  try {
    const raw = await Search(data.keyword, data.searchMethod, data.limit)
    const parsed = JSON.parse(raw)

    // Ensure the result is always an array
    data.results = Array.isArray(parsed) ? parsed : []
  } catch (err) {
    console.error('Search failed:', err)
    data.results = [] // fallback to empty array to avoid breaking v-for
  }
}

</script>

<template>
  <main class="container">
    <section>
        <form class="controls" @submit.prevent="search">
            <input
                v-model="data.keyword"
                type="text"
                class="input flex-grow"
                placeholder="Enter keyword..."
            />
            <input
                v-model.number="data.limit"
                type="number"
                class="input short"
                placeholder="Limit"
                min="1"
            />
            <select v-model="data.searchMethod" class="input medium">
            <option value="balochi">Balochi</option>
            <option value="latin">Latin</option>
            <option value="definition">Definition</option>
            </select>
            <button class="btn" @click="search">Search</button>
        </form>
    </section>

    <section class="results">
      <div v-if="data.results.length === 0">No results</div>
      <div v-else>
        <div v-for="word in data.results" :key="word.WordID" class="card">
          <h3>{{ word.Balochi }} <small>({{ word.Latin }})</small></h3>
          <p><strong>Normalized:</strong> {{ word.NormalizedLatin }}</p>
          <ul>
            <li v-for="(def, index) in word.Definitions" :key="index">
              <em>{{ def.PartOfSpeech }}:</em> {{ def.Text }}
            </li>
          </ul>
        </div>
      </div>
    </section>
  </main>
</template>

<style scoped>
.container {
  padding: 2rem;
  font-family: sans-serif;
  background-color: #222831;
  color: #e0e0e0;
  min-height: 100vh;
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

.input::placeholder {
  color: #888;
}

.input.short {
  width: 80px;
}

.input.medium {
  width: 150px;
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

.card {
  background-color: #393E46;
  color: #f0f0f0;
  padding: 1rem;
  border-radius: 8px;
  box-shadow: 0 0 6px rgba(0, 0, 0, 0.4);
  margin-bottom: 1rem;
}

.results h3 {
  margin: 0 0 0.25rem 0;
}

.results ul {
  margin: 0.5rem 0 0 1rem;
  padding: 0;
  list-style-type: disc;
}

.results em {
  color: #a0cfff;
}

.left-controls,
.right-controls {
  display: flex;
  flex-grow: 1;
  gap: 1rem;
  flex-wrap: wrap;
}

.small-input {
  max-width: 80px;
}

.flex-grow {
  flex-grow: 1;
}

</style>

