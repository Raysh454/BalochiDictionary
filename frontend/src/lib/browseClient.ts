export type BrowseItem = {
  WordID: number
  Balochi: string
  Latin: string
  NormalizedLatin: string
}

export type BrowseDefinition = {
  PartOfSpeech: string
  Text: string
}

export type BrowseItemDetail = BrowseItem & {
  Definitions: BrowseDefinition[]
}

export type BrowsePagination = {
  offset: number
  limit: number
  nextOffset: number
  hasMore: boolean
}

export type BrowsePage = {
  items: BrowseItem[]
  pagination: BrowsePagination
  filter: {
    letter: string
  }
}

export type BrowseLetter = {
  letter: string
  count: number
}

export async function browseDictionary(
  letter: string,
  limit: number,
  offset: number,
  signal?: AbortSignal,
): Promise<BrowsePage> {
  const params = new URLSearchParams({
    limit: String(limit),
    offset: String(offset),
  })

  if (letter) {
    params.set('letter', letter)
  }

  const response = await fetch(`/api/browse?${params.toString()}`, { signal })
  if (!response.ok) {
    throw new Error(await response.text())
  }

  return response.json()
}

export async function browseLetters(): Promise<BrowseLetter[]> {
  const response = await fetch('/api/browse/letters')
  if (!response.ok) {
    throw new Error(await response.text())
  }

  const parsed = await response.json()
  return Array.isArray(parsed?.letters) ? parsed.letters : []
}

export async function browseItemDetail(wordID: number, signal?: AbortSignal): Promise<BrowseItemDetail> {
  const params = new URLSearchParams({
    word_id: String(wordID),
  })

  const response = await fetch(`/api/browse/item?${params.toString()}`, { signal })
  if (!response.ok) {
    throw new Error(await response.text())
  }

  return response.json()
}
