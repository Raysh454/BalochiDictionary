export type Definition = {
  PartOfSpeech: string
  Text: string
}

export type DictionaryResult = {
  WordID: number
  Balochi: string
  Latin: string
  NormalizedLatin: string
  Definitions: Definition[]
}

type WailsAppBridge = {
  Search: (keyword: string, method: string, limit: number) => Promise<string>
}

type WailsBridgeWindow = Window & {
  go?: {
    main?: {
      App?: WailsAppBridge
    }
  }
}

function getWailsBridge(): WailsAppBridge | undefined {
  const app = (window as WailsBridgeWindow).go?.main?.App
  if (app && typeof app.Search === 'function') {
    return app
  }
  return undefined
}

export async function searchDictionary(
  keyword: string,
  searchMethod: string,
  limit: number
): Promise<DictionaryResult[]> {
  const wailsBridge = getWailsBridge()
  if (wailsBridge) {
    const raw = await wailsBridge.Search(keyword, searchMethod, limit)
    const parsed = JSON.parse(raw)
    return Array.isArray(parsed) ? parsed : []
  }

  const params = new URLSearchParams({
    keyword,
    method: searchMethod,
    limit: String(limit),
  })

  const response = await fetch(`/api/search?${params.toString()}`)
  if (!response.ok) {
    throw new Error(await response.text())
  }

  const parsed = await response.json()
  return Array.isArray(parsed) ? parsed : []
}
