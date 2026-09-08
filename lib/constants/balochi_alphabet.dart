/// Port of `frontend/src/constants/balochiAlphabet.ts`.
class BalochiAlphabetLetter {
  const BalochiAlphabetLetter(this.letter, this.name);

  final String letter;
  final String name;
}

const List<BalochiAlphabetLetter> balochiAlphabet = [
  BalochiAlphabetLetter('ا', 'Aliph'),
  BalochiAlphabetLetter('آ', 'Aliph madda'),
  BalochiAlphabetLetter('ب', 'Bay'),
  BalochiAlphabetLetter('پ', 'Pay'),
  BalochiAlphabetLetter('ت', 'Tay'),
  BalochiAlphabetLetter('ٹ', 'Ttay'),
  BalochiAlphabetLetter('ث', 'Say'),
  BalochiAlphabetLetter('ج', 'Jeem'),
  BalochiAlphabetLetter('چ', 'Chay'),
  BalochiAlphabetLetter('ح', 'Hay'),
  BalochiAlphabetLetter('خ', 'Khay'),
  BalochiAlphabetLetter('د', 'Dal'),
  BalochiAlphabetLetter('ڈ', 'Ddal'),
  BalochiAlphabetLetter('ذ', 'Zal'),
  BalochiAlphabetLetter('ر', 'Ray'),
  BalochiAlphabetLetter('ڑ', 'Rray'),
  BalochiAlphabetLetter('ز', 'Zay'),
  BalochiAlphabetLetter('ژ', 'Zhay'),
  BalochiAlphabetLetter('س', 'Seen'),
  BalochiAlphabetLetter('ش', 'Sheen'),
  BalochiAlphabetLetter('ص', 'Suad'),
  BalochiAlphabetLetter('ض', 'Zuad'),
  BalochiAlphabetLetter('ط', 'Toay'),
  BalochiAlphabetLetter('ظ', 'Zoay'),
  BalochiAlphabetLetter('ع', 'Ain'),
  BalochiAlphabetLetter('غ', 'Ghain'),
  BalochiAlphabetLetter('ف', 'Fay'),
  BalochiAlphabetLetter('ق', 'Qaf'),
  BalochiAlphabetLetter('ک', 'Kaf'),
  BalochiAlphabetLetter('گ', 'Gaf'),
  BalochiAlphabetLetter('ل', 'Lam'),
  BalochiAlphabetLetter('م', 'Meem'),
  BalochiAlphabetLetter('ن', 'Noon'),
  BalochiAlphabetLetter('ں', 'Noon ghunna'),
  BalochiAlphabetLetter('و', 'Waw'),
  BalochiAlphabetLetter('ہ', 'Hay do chashmi'),
  BalochiAlphabetLetter('ھ', 'Do chashmi hay'),
  BalochiAlphabetLetter('ء', 'Hamza'),
  BalochiAlphabetLetter('ی', 'Choti yay'),
  BalochiAlphabetLetter('ے', 'Bari yay'),
];
