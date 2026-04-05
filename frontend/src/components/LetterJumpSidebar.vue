<script lang="ts" setup>
import { BALOCHI_ALPHABET } from '../constants/balochiAlphabet'

defineProps<{
  activeLetter: string
  letterCounts: Record<string, number>
}>()

const emit = defineEmits<{
  (event: 'jump', letter: string): void
}>()

function jumpToLetter(letter: string) {
  emit('jump', letter)
}
</script>

<template>
  <aside class="letter-sidebar" aria-label="Balochi alphabet jump links">
    <button class="letter-btn all" :class="{ active: !activeLetter }" type="button" @click="jumpToLetter('')">
      All
    </button>
    <button
      v-for="entry in BALOCHI_ALPHABET"
      :key="entry.letter"
      class="letter-btn"
      :class="{ active: activeLetter === entry.letter, disabled: !letterCounts[entry.letter] }"
      :title="`${entry.name}${letterCounts[entry.letter] ? ` (${letterCounts[entry.letter]})` : ''}`"
      type="button"
      @click="jumpToLetter(entry.letter)"
    >
      {{ entry.letter }}
    </button>
  </aside>
</template>

<style scoped>
.letter-sidebar {
  position: fixed;
  right: 0.75rem;
  top: 8.25rem;
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
  max-height: calc(100vh - 9rem);
  overflow-y: auto;
  background-color: rgba(30, 30, 30, 0.95);
  border: 1px solid #444;
  border-radius: 8px;
  padding: 0.5rem 0.35rem;
}

.letter-btn {
  border: 1px solid #444;
  border-radius: 4px;
  background: #1e1e1e;
  color: #ddd;
  min-width: 2rem;
  height: 1.75rem;
  cursor: pointer;
  font-weight: 700;
  line-height: 1;
}

.letter-btn:hover {
  background: #5588dd;
  border-color: #5588dd;
  color: #fff;
}

.letter-btn.active {
  background: #3366cc;
  border-color: #3366cc;
  color: #fff;
}

.letter-btn.disabled {
  opacity: 0.55;
}

.letter-btn.all {
  font-size: 0.7rem;
  min-width: 2.2rem;
}
</style>
