import 'package:flutter/material.dart';

/// Global locale notifier so user can change language anywhere in the app.
final ValueNotifier<Locale> appLocaleNotifier = ValueNotifier<Locale>(
  const Locale('en'),
);

bool isPersian(BuildContext context) {
  return Localizations.localeOf(context).languageCode == 'fa';
}

class AppStrings {
  final BuildContext context;
  AppStrings(this.context);

  static AppStrings of(BuildContext context) => AppStrings(context);

  bool get isFa => isPersian(context);

  String get appTitle => isFa ? 'طبقه‌بندی ضربان قلب ECG' : 'ECG Beat Classifier';
  String get appVersion => 'V2.0.0';

  String get appTagline => isFa
      ? 'طبقه‌بندی ضربان‌های تک‌لید به دسته‌های N، S و V. تمام پردازش‌ها کاملاً آفلاین روی گوشی اجرا می‌شوند.'
      : 'Classify single-lead heartbeats as N, S or V. Everything runs on this phone, offline.';

  String get demoRecords => isFa ? 'نمونه‌های پیش‌فرض' : 'Demo records';
  String get yourOwnSignal => isFa ? 'سیگنال انتخابی شما' : 'Your own signal';
  String get importCsv => isFa ? 'بارگذاری فایل CSV' : 'Import CSV';

  String imported(String name) => isFa ? 'بارگذاری شد: $name' : 'Imported: $name';

  String samplesCount(int count, int skipped) {
    if (isFa) {
      final skipText = skipped > 0 ? ' · $skipped سطر نادیده گرفته شد' : '';
      return '$count نمونه داده$skipText';
    }
    return '$count samples${skipped > 0 ? ' · $skipped lines ignored' : ''}';
  }

  String get samplingRateLabel => isFa ? 'نرخ نمونه‌برداری (Hz)' : 'Sampling rate (Hz)';
  String get samplingRateHelper => isFa
      ? 'بین ۱۰۰ تا ۲۰۰۰ هرتز. نمونه‌های پیش‌فرض ۳۶۰ هرتز هستند.'
      : 'Between 100 and 2000. Demo records are 360 Hz.';

  String get validateRateNumber => isFa
      ? 'یک عدد معتبر وارد کنید، مثلاً ۳۶۰.'
      : 'Enter a number, for example 360.';

  String get validateRateRange => isFa
      ? 'نرخ نمونه‌برداری باید بین ۱۰۰ تا ۲۰۰۰ هرتز باشد.'
      : 'Sampling rate must be between 100 and 2000 Hz.';

  String get noNumbersInFile => isFa
      ? 'هیچ داده عددی در فایل پیدا نشد. انتظار می‌رفت در هر سطر یک مقدار ECG یا ستون‌های جدا شده با ویرگول باشد.'
      : 'No numbers found in that file. Expected one ECG value per line, or comma separated columns.';

  String couldNotReadFile(Object e) => isFa ? 'خطا در خواندن فایل: $e' : 'Could not read that file: $e';

  String get pickRecordFirst => isFa
      ? 'ابتدا یک نمونه پیش‌فرض انتخاب کنید یا فایل CSV را بارگذاری نمایید.'
      : 'Pick a demo record or import a CSV first.';

  String signalTooShort(String seconds) => isFa
      ? 'طول این سیگنال فقط $seconds ثانیه است. برای تشخیص ضربان‌ها حداقل ۱۰ ثانیه سیگنال نیاز است.'
      : 'That signal is only $seconds s long. I need at least 10 s to find enough heartbeats.';

  String get noBeatsDetected => isFa
      ? 'هیچ ضربان قلبی شناسایی نشد. نرخ نمونه‌برداری و تک‌لید بودن فایل را بررسی کنید.'
      : 'No heartbeats detected. Check the sampling rate and that the file holds a single ECG lead.';

  String analysisFailed(Object e) => isFa ? 'تحلیل با خطا مواجه شد: $e' : 'Analysis failed: $e';

  String get analyze => isFa ? 'تحلیل و پردازش' : 'Analyze';
  String get analyzing => isFa ? 'در حال تحلیل…' : 'Analyzing…';

  String get disclaimer => isFa
      ? 'پروژه آموزشی و پژوهشی، فاقد کاربرد تشخیصی پزشکی.'
      : 'Educational project, not a medical device.';

  String get aboutTooltip => isFa ? 'درباره' : 'About';
  String get aboutTitle => isFa ? 'درباره برنامه' : 'About';
  String get aboutHeadline => isFa ? 'طبقه‌بندی ضربان قلب ECG' : 'ECG Beat Classifier';
  String get aboutTagline => isFa
      ? 'طبقه‌بندی تک‌لید ضربان قلب، کاملاً آفلاین روی گوشی.'
      : 'Single-lead heartbeat classification, fully on-device.';

  String get dataSectionTitle => isFa ? 'داده‌ها' : 'Data';
  String get dataDesc1 => isFa
      ? 'پایگاه داده آریتمی MIT-BIH (PhysioNet): شامل ۴۸ رکورد نیم‌ساعته دو لید با فرکانس ۳۶۰ هرتز همراه با برچسب‌گذاری دقیق متخصصان. فقط از لید اول (MLII) استفاده شده است.'
      : 'MIT-BIH Arrhythmia Database (PhysioNet): 48 half-hour two-lead recordings at 360 Hz with expert beat annotations. Only the first lead (MLII) is used.';

  String get dataDesc2 => isFa
      ? 'تفکیک بین‌بیماری (Inter-patient): ۲۲ بیمار برای آموزش و ۲۲ بیمار مجزا برای آزمون، به طوری که داده‌های هیچ بیماری در هر دو مجموعه مشترک نیست.'
      : 'Inter-patient split: 22 patients for training and 22 different patients for testing, so no patient appears in both sets.';

  String get testResultsTitle => isFa ? 'نتایج آزمون' : 'Test results';
  String get testResultsSubtitle => isFa ? '۲۲ بیمار مجزا در داده‌های آزمون' : '22 unseen test patients';

  String get labelNF1 => isFa ? 'امتیاز F1 ضربان N' : 'N F1';
  String get labelVF1 => isFa ? 'امتیاز F1 ضربان V' : 'V F1';
  String get labelSF1 => isFa ? 'امتیاز F1 ضربان S' : 'S F1';
  String get labelMacroF1 => isFa ? 'میانگین کلی Macro F1 (N, S, V)' : 'Macro F1 (N, S, V)';

  String get limitationsTitle => isFa ? 'محدودیت‌ها' : 'Limitations';
  String get limitationS => isFa
      ? 'ضربان‌های S ضعیف‌تر هستند: از نظر شکل موج بسیار شبیه ضربان‌های نرمال بوده و عمدتاً در زمان‌بندی تفاوت دارند.'
      : 'S beats are weak: they look very similar to normal beats and differ mostly in timing.';

  String get limitationF => isFa
      ? 'ضربان‌های ترکیبی یا فیوژن (F) توسط این مدل پیش‌بینی نمی‌شوند.'
      : 'Fusion (F) beats are not predicted at all.';

  String get limitationSingleLead => isFa
      ? 'فقط تک‌لید و فقط یک پایگاه داده؛ بر روی سایر دستگاه‌ها یا جوامع اعتبارسنجی نشده است.'
      : 'Single lead only, and only one database. Not validated on other devices or populations.';

  String get beatsAnalyzed => isFa ? 'تعداد ضربان‌های تحلیل‌شده' : 'Beats analyzed';
  String get heartRate => isFa ? 'ضربان قلب' : 'Heart rate';
  String bpmValue(int? bpm) => bpm == null ? '—' : (isFa ? '$bpm ضربان/دقیقه' : '$bpm bpm');

  String get sBeats => isFa ? 'ضربان‌های S' : 'S beats';
  String get vBeats => isFa ? 'ضربان‌های V' : 'V beats';

  String get ecgSignal => isFa ? 'سیگنال ECG' : 'ECG signal';
  String windowLabel(int s) => isFa ? 'پنجره $s ثانیه‌ای' : '$s s window';

  String get beatCounts => isFa ? 'تعداد بر اساس رده' : 'Beat counts';
  String get sAndVBeats => isFa ? 'ضربان‌های S و V' : 'S and V beats';
  String get noArrhythmiaDetected => isFa ? 'موردی در این سیگنال شناسایی نشد.' : 'None detected in this signal.';
  String get tapToJump => isFa
      ? 'برای پرش به هر ضربان در نمودار، ردیف آن را لمس کنید.'
      : 'Tap a row to jump to that beat in the plot.';

  String sampleTitle(String id, String defaultTitle) {
    if (!isFa) return defaultTitle;
    switch (id) {
      case '200':
        return 'رکورد ۲۰۰';
      case '100':
        return 'رکورد ۱۰۰';
      case '233':
        return 'رکورد ۲۳۳';
      default:
        return defaultTitle;
    }
  }

  String sampleSubtitle(String id, String defaultSubtitle) {
    if (!isFa) return defaultSubtitle;
    switch (id) {
      case '200':
        return '۶۰ ثانیه · چندین ضربان بطنی (V)';
      case '100':
        return '۶۰ ثانیه · ریتم طبیعی و منظم (N)';
      case '233':
        return '۶۰ ثانیه · ریتم آریتمی مختلط';
      default:
        return defaultSubtitle;
    }
  }

  String classLabelLong(int index) {
    if (isFa) {
      switch (index) {
        case 0:
          return 'طبیعی (Normal)';
        case 1:
          return 'فوق‌بطنی (Supraventricular)';
        case 2:
          return 'بطنی (Ventricular)';
        case 3:
          return 'ترکیبی (Fusion)';
        default:
          return 'نامشخص';
      }
    }
    switch (index) {
      case 0:
        return 'Normal';
      case 1:
        return 'Supraventricular';
      case 2:
        return 'Ventricular';
      case 3:
        return 'Fusion';
      default:
        return 'Unknown';
    }
  }

  String get languageToggle => isFa ? 'English' : 'فارسی';
  String get languageTooltip => isFa ? 'تغییر زبان به انگلیسی' : 'تغییر زبان به فارسی';
}
