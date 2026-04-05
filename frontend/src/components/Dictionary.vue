<script lang="ts" setup>
import { ref } from 'vue'
import BrowseTab from './BrowseTab.vue'
import SearchTab from './SearchTab.vue'

type Tab = 'browse' | 'search'

const activeTab = ref<Tab>('browse')
</script>

<template>
  <main class="container">
    <nav class="tabs" aria-label="Dictionary views">
      <button class="tab" :class="{ active: activeTab === 'browse' }" @click="activeTab = 'browse'">
        Browse
      </button>
      <button class="tab" :class="{ active: activeTab === 'search' }" @click="activeTab = 'search'">
        Search
      </button>
    </nav>

    <section class="tab-content">
      <BrowseTab v-show="activeTab === 'browse'" />
      <SearchTab v-show="activeTab === 'search'" />
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

.tabs {
  display: flex;
  justify-content: flex-start;
  gap: 1rem;
  margin-bottom: 2rem;
}

.tab {
  padding: 0.5rem 1rem;
  border: 1px solid #444;
  border-radius: 5px;
  background-color: #1e1e1e;
  color: #ddd;
  font-weight: bold;
  cursor: pointer;
}

.tab.active {
  background: #3366cc;
  color: #fff;
  border-color: #3366cc;
}

.tab-content {
  text-align: left;
}
</style>
