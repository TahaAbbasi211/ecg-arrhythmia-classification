import 'package:flutter/material.dart';

import '../data/signal_units.dart';

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
  String get appVersion => 'V3.1.0';

  String get appTagline => isFa
      ? 'طبقه‌بندی ضربان‌های تک‌لید به دسته‌های N، S و V. تمام پردازش‌ها کاملاً آفلاین روی گوشی اجرا می‌شوند.'
      : 'Classify single-lead heartbeats as N, S or V. Everything runs on this phone, offline.';

  String get demoRecords => isFa ? 'نمونه‌های پیش‌فرض' : 'Demo records';
  String get yourOwnSignal => isFa ? 'سیگنال انتخابی شما' : 'Your own signal';
  String get importCsv => isFa ? 'بارگذاری فایل CSV' : 'Import CSV';

  String imported(String name) => isFa ? 'بارگذاری شد: $name' : 'Imported: $name';

  String get importedCsvTitle => isFa ? 'فایل CSV بارگذاری‌شده' : 'Imported CSV';

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

  String get signalUnitLabel => isFa ? 'واحد سیگنال' : 'Signal unit';
  String get signalUnitHelper => isFa
      ? 'واحد مقادیر فایل. رکوردهای نمونه بر حسب میلی‌ولت هستند.'
      : 'Unit of the numbers in the file. Demo records are in millivolts.';

  String unitLabel(SignalUnit unit) {
    switch (unit) {
      case SignalUnit.millivolt:
        return isFa ? 'میلی‌ولت (mV)' : 'Millivolts (mV)';
      case SignalUnit.volt:
        return isFa ? 'ولت (×۱۰۰۰)' : 'Volts (x1000)';
      case SignalUnit.microvolt:
        return isFa ? 'میکروولت (÷۱۰۰۰)' : 'Microvolts (/1000)';
    }
  }

  String get invertPolarity => isFa ? 'معکوس کردن پلاریته' : 'Invert polarity';
  String get invertPolarityHelp => isFa
      ? 'اگر ضربان‌ها در نمودار برعکس دیده می‌شوند، این گزینه را روشن کنید.'
      : 'Turn this on when the beats point the wrong way in the plot.';

  String get amplitudeWarningTitle => isFa ? 'واحد سیگنال مشکوک است' : 'The signal unit looks wrong';
  String amplitudeTooSmall(String value) => isFa
      ? 'دامنه سیگنال پس از فیلتر فقط $value است. طبقه‌بندی مدل اکنون مقیاس‌ناورداست و تغییر نمی‌کند، اما احتمالاً فایل بر حسب ولت است و تبدیل واحد برای نمایش دقیق محور عمودی (mV) در نمودار است.'
      : 'The filtered signal spans only $value. Model classification is scale-invariant, so predictions stay unchanged, but the file is probably in volts; converting updates the mV vertical axis on the plot.';
  String amplitudeTooLarge(String value) => isFa
      ? 'دامنه سیگنال پس از فیلتر حدود $value است. طبقه‌بندی مدل اکنون مقیاس‌ناورداست و تغییر نمی‌کند، اما احتمالاً فایل بر حسب میکروولت یا شمارنده خام ADC است و تبدیل واحد برای نمایش دقیق محور عمودی (mV) در نمودار است.'
      : 'The filtered signal spans about $value. Model classification is scale-invariant, so predictions stay unchanged, but the file is probably in microvolts or raw ADC counts; converting updates the mV vertical axis on the plot.';
  String get continueAnyway => isFa ? 'ادامه' : 'Continue anyway';
  String convertToUnit(String unit) =>
      isFa ? 'تبدیل به $unit و تحلیل دوباره' : 'Convert to $unit and analyze again';

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
      ? 'نرم‌افزار پژوهشی و غیربالینی — دستگاه پزشکی دارای تأییدیه نیست و برای تشخیص بالینی یا تصمیم‌گیری درمانی طراحی نشده است.'
      : 'Research and non-clinical software — not a certified medical device and not intended for clinical diagnosis or treatment decisions.';

  String get aboutTooltip => isFa ? 'درباره' : 'About';
  String get aboutTitle => isFa ? 'درباره برنامه' : 'About';
  String get aboutHeadline => isFa ? 'طبقه‌بندی ضربان قلب ECG' : 'ECG Beat Classifier';
  String get aboutTagline => isFa
      ? 'طبقه‌بندی تک‌لید ضربان قلب، کاملاً آفلاین روی گوشی.'
      : 'Single-lead heartbeat classification, fully on-device.';

  String get dataSectionTitle => isFa ? 'داده‌ها' : 'Data';
  String get dataDesc1 => isFa
      ? 'پایگاه داده آریتمی MIT-BIH (PhysioNet): شامل ۴۸ رکورد نیم‌ساعته دو لید با فرکانس ۳۶۰ هرتز همراه با برچسب‌گذاری دقیق متخصصان. فقط از لید MLII استفاده شده است.'
      : 'MIT-BIH Arrhythmia Database (PhysioNet): 48 half-hour two-lead recordings at 360 Hz with expert beat annotations. Only lead MLII is used.';

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
      ? 'ضربان‌های S ضعیف‌ترند (F1 کل ۰.۱۷۹ و روی ۲۱ بیمار بدون رکورد ۲۳۲ برابر ۰.۴۰۷): از نظر شکل موج بسیار شبیه ضربان‌های نرمال بوده و عمدتاً در زمان‌بندی و موج P تفاوت دارند.'
      : 'S beats are weak overall (F1 0.179 across DS2; 0.407 excluding record 232): they look very similar to normal beats and differ mostly in timing and P-wave shape.';

  String get limitationSustainedAtrial => isFa
      ? 'در ریتم‌های دهلیزی مداوم که اکثر ضربان‌های نوار غیرطبیعی‌اند (مانند رکورد ۲۳۲)، الگوی میانه بیمار و ریتم محلی با خود ریتم غیرطبیعی تنظیم می‌شوند و حساسیت S کاهش می‌یابد.'
      : 'In sustained ectopic atrial rhythms where most beats in the strip are abnormal (such as MIT-BIH record 232), the recording-median template and local rhythm adapt to the abnormal rhythm, reducing S recall.';

  String get limitationF => isFa
      ? 'ضربان‌های ترکیبی یا فیوژن (F) توسط این مدل پیش‌بینی نمی‌شوند.'
      : 'Fusion (F) beats are not predicted at all.';

  String get limitationSingleLead => isFa
      ? 'فقط تک‌لید و ارزیابی‌شده روی پایگاه‌های داده پژوهشی (MIT-BIH و SVDB)؛ بر روی سایر دستگاه‌ها یا جوامع بالینی اعتبارسنجی نشده است.'
      : 'Single lead only, evaluated on research databases (MIT-BIH and SVDB). Not validated on other devices or clinical populations.';

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
  String get languageTooltip => isFa ? 'تغییر زبان به انگلیسی' : 'Switch to Persian';
}
