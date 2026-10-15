part of 'main.dart';

class MemoLanguage extends ThemeExtension<MemoLanguage> {
  const MemoLanguage(this.code);
  final String code;
  @override
  MemoLanguage copyWith({String? code}) => MemoLanguage(code ?? this.code);
  @override
  MemoLanguage lerp(covariant MemoLanguage? other, double t) =>
      t < .5 ? this : other ?? this;
}

String uiText(BuildContext context, String zh, String en) =>
    Theme.of(context).extension<MemoLanguage>()?.code == 'en' ? en : zh;

const memoLocales = [Locale('zh'), Locale('en')];
const memoDelegates = GlobalMaterialLocalizations.delegates;
