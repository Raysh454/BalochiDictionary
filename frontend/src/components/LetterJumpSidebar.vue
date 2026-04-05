<script lang="ts" setup>
import { computed } from 'vue'
import { BALOCHI_ALPHABET } from '../constants/balochiAlphabet'

const props = defineProps<{
  activeLetter: string
  letterCounts: Record<string, number>
}>()

const emit = defineEmits<{
  (event: 'jump', letter: string): void
}>()

function jumpToLetter(letter: string) {
  emit('jump', letter)
}

const visibleLetters = computed(() => {
  return BALOCHI_ALPHABET.filter((entry) => (props.letterCounts[entry.letter] ?? 0) > 0)
})
</script>

<template>
  <aside class="letter-sidebar" aria-label="Balochi alphabet jump links">
    <button class="letter-btn all" :class="{ active: !props.activeLetter }" type="button" @click="jumpToLetter('')">
      All
    </button>
    <button
      v-for="entry in visibleLetters"
      :key="entry.letter"
      class="letter-btn"
      :class="{ active: props.activeLetter === entry.letter }"
      :title="`${entry.name} (${props.letterCounts[entry.letter]})`"
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

.letter-btn.all {
  font-size: 0.7rem;
  min-width: 2.2rem;
}
</style>
