import unicodedata
# s = '_EP第9999话_P9999.png'
#s = '與明明看起來很清純卻用下流的言辭呻吟起來的鄰家巨乳大姐姐濃厚親密恩愛性愛的故事 [ひつじのうどん屋 (いなみみ)] 清楚っぽいのに下品な言葉づかいでオホ喘ぎしち_EP第1.png'
s = '與明明看起來很清純卻用下流的言辭呻吟起來的鄰家巨乳大姐姐濃厚親密恩愛性愛的故事 [ひつじのうどん屋 (いなみみ)] 清楚っぽいのに下品な言葉づかいでオホ喘ぎしち'
# s = '與明明看起來很清純卻用下流的言辭呻吟起來的鄰家巨乳大姐姐濃厚親密恩愛性愛的故事 [ひつじのうどん屋 (いなみみ)] 清楚っぽいのに下品な言葉づかいでオ_EP第1話_P55.png'
# s = '與明明看起來很清純卻用下流的言辭呻吟起來的鄰家巨乳大姐姐濃厚親密恩愛性愛的故事 [ひつじのうどん屋 (いなみみ)] 清楚っぽいのに下品な言葉づかいでオ_EP第1話_P1.png'
# s = 'じ'
print('python len(code points):', len(s))
print('utf8 bytes:', len(s.encode('utf-8')))
print('combining count:', sum(1 for ch in s if unicodedata.combining(ch)))
print('combining chars:', [(i, ch, hex(ord(ch)), unicodedata.name(ch, '?')) for i,ch in enumerate(s) if unicodedata.combining(ch)])
# utf-16 code units like Dart String.length for BMP-only this equals code points; surrogate pairs would differ.
print('non-bmp count:', sum(1 for ch in s if ord(ch) > 0xFFFF))
print('nfc len:', len(unicodedata.normalize('NFC', s)))
print('nfd len:', len(unicodedata.normalize('NFD', s)))
print('nfc string:', unicodedata.normalize('NFC', s))

