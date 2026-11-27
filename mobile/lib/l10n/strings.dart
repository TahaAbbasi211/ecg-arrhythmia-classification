import 'package:flutter/material.dart';

import '../data/signal_units.dart';

/// Global locale notifier so the user can switch EN / FA anywhere in the app.
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

  String get appTitle =>
      isFa ? 'طبقه‌بندی ضربان قلب ECG' : 'ECG Beat Classifier';
  String get brandName => 'BIOVANTA · ECG';
  String get appVersion => 'V4.0.0';
  String get heroStatusPill => isFa
      ? 'آفلاین · ۸۴ ویژگی · 163 KB HGB'
      : 'Offline · 84 Features · 163 KB HGB';

  String get appTagline => isFa
      ? 'مانیتور تله‌متری تک‌لید ضربان قلب (N، S، V) — پردازش کاملاً آفلاین روی دستگاه بدون نیاز به اینترنت.'
      : 'Single-lead ECG rhythm instrument (N, S, V) — deterministic DSP and 84-feature HGB inference 100% on-device.';

  // Bottom 3-tab dock
  String get navMonitor => isFa ? 'مانیتور' : 'Monitor';
  String get navStudio => isFa ? 'استودیو' : 'Studio';
  String get navLabInfo => isFa ? 'آزمایشگاه' : 'Lab & Info';

  // Theme controls
  String get themeLabel => isFa ? 'پوسته نمایش' : 'Appearance';
  String get themeDark => isFa ? 'تاریک' : 'Dark';
  String get themeLight => isFa ? 'روشن' : 'Light';
  String get themeSystem => isFa ? 'سیستم' : 'System';
  String get themeTooltip => isFa ? 'تغییر پوسته نمایش' : 'Switch theme';

  // Language controls
  String get languageSectionLabel => isFa ? 'زبان برنامه' : 'Language';
  String get languageToggle => isFa ? 'English' : 'فارسی';
  String get languageTooltip =>
      isFa ? 'تغییر زبان به انگلیسی' : 'Switch to Persian';

  // Monitor tab — Demo deck & Import
  String get demoRecords =>
      isFa ? 'نمونه‌های پیش‌فرض MIT-BIH' : 'Demo records · MIT-BIH';
  String get demoDeckHint => isFa
      ? 'برای انتخاب ورق بزنید یا با یک لمس تحلیل کنید'
      : 'Swipe to browse or tap quick-analyze';
  String get tapToAnalyze => isFa ? 'تحلیل سریع' : 'Quick run';
  String get activeBadge => isFa ? 'انتخاب‌شده' : 'Active';

  String get yourOwnSignal =>
      isFa ? 'ورود سیگنال دلخواه (CSV / TXT)' : 'Custom Signal Import';
  String get importCsv => isFa ? 'بارگذاری فایل CSV / TXT' : 'Import CSV / TXT';
  String get importSubtitle => isFa
      ? 'پشتیبانی از فایل‌های ۱، ۲ و ۳ ستونی (حداکثر ۲۰ مگابایت)'
      : 'Supports 1-, 2-, and 3-column recordings up to 20 MB';
  String imported(String name) => isFa ? 'بارگذاری شد: $name' : 'Imported: $name';
  String get importedCsvTitle => isFa ? 'فایل CSV بارگذاری‌شده' : 'Imported CSV';

  String samplesCount(int count, int skipped) {
    if (isFa) {
      final skipText = skipped > 0 ? ' · $skipped سطر نادیده گرفته شد' : '';
      return '$count نمونه داده$skipText';
    }
    return '$count samples${skipped > 0 ? ' · $skipped lines skipped' : ''}';
  }

  // Calibration drawer
  String get calibrationTitle =>
      isFa ? 'کالیبراسیون و تنظیمات سیگنال' : 'Signal Calibration';
  String get samplingRateLabel =>
      isFa ? 'نرخ نمونه‌برداری (Hz)' : 'Sampling rate (Hz)';
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
      : 'Flip signal orientation when beats point upside down.';

  // Recent sessions strip
  String get recentAnalyses => isFa ? 'تحلیل‌های اخیر نشست' : 'Recent analyses';

  // Sanity dialog & validation errors
  String get amplitudeWarningTitle =>
      isFa ? 'واحد سیگنال مشکوک است' : 'The signal unit looks wrong';
  String amplitudeTooSmall(String value) => isFa
      ? 'دامنه سیگنال پس از فیلتر فقط $value است. طبقه‌بندی مدل مقیاس‌ناورداست و تغییر نمی‌کند، اما احتمالاً فایل بر حسب ولت است و تبدیل واحد برای نمایش دقیق محور عمودی (mV) در نمودار است.'
      : 'The filtered signal spans only $value. Model classification is scale-invariant, so predictions stay unchanged, but the file is probably in volts; converting updates the mV vertical axis on the plot.';
  String amplitudeTooLarge(String value) => isFa
      ? 'دامنه سیگنال پس از فیلتر حدود $value است. طبقه‌بندی مدل مقیاس‌ناورداست و تغییر نمی‌کند، اما احتمالاً فایل بر حسب میکروولت یا شمارنده خام ADC است و تبدیل واحد برای نمایش دقیق محور عمودی (mV) در نمودار است.'
      : 'The filtered signal spans about $value. Model classification is scale-invariant, so predictions stay unchanged, but the file is probably in microvolts or raw ADC counts; converting updates the mV vertical axis on the plot.';
  String get continueAnyway => isFa ? 'ادامه' : 'Continue anyway';
  String convertToUnit(String unit) => isFa
      ? 'تبدیل به $unit و تحلیل دوباره'
      : 'Convert to $unit and analyze again';

  String get validateRateNumber =>
      isFa ? 'یک عدد معتبر وارد کنید، مثلاً ۳۶۰.' : 'Enter a number, for example 360.';
  String get validateRateRange => isFa
      ? 'نرخ نمونه‌برداری باید بین ۱۰۰ تا ۲۰۰۰ هرتز باشد.'
      : 'Sampling rate must be between 100 and 2000 Hz.';
  String get noNumbersInFile => isFa
      ? 'هیچ داده عددی در فایل پیدا نشد. انتظار می‌رفت در هر سطر یک مقدار ECG یا ستون‌های جدا شده با ویرگول باشد.'
      : 'No numbers found in that file. Expected one ECG value per line, or comma separated columns.';
  String couldNotReadFile(Object e) =>
      isFa ? 'خطا در خواندن فایل: $e' : 'Could not read that file: $e';
  String get pickRecordFirst => isFa
      ? 'ابتدا یک نمونه پیش‌فرض انتخاب کنید یا فایل CSV را بارگذاری نمایید.'
      : 'Pick a demo record or import a CSV first.';
  String signalTooShort(String seconds) => isFa
      ? 'طول این سیگنال فقط $seconds ثانیه است. برای تشخیص ضربان‌ها حداقل ۱۰ ثانیه سیگنال نیاز است.'
      : 'That signal is only $seconds s long. I need at least 10 s to find enough heartbeats.';
  String get noBeatsDetected => isFa
      ? 'هیچ ضربان قلبی شناسایی نشد. نرخ نمونه‌برداری و تک‌لید بودن فایل را بررسی کنید.'
      : 'No heartbeats detected. Check the sampling rate and that the file holds a single ECG lead.';
  String analysisFailed(Object e) =>
      isFa ? 'تحلیل با خطا مواجه شد: $e' : 'Analysis failed: $e';

  String get analyze => isFa ? 'تحلیل و پردازش' : 'Analyze';
  String get analyzing => isFa ? 'در حال تحلیل…' : 'Analyzing…';

  // Studio Tab — Empty state & Telemetry HUD
  String get studioEmptyTitle =>
      isFa ? 'هنوز ضربانی در استودیو بارگذاری نشده' : 'Studio Waiting for Signal';
  String get studioEmptySubtitle => isFa
      ? 'به تب مانیتور بروید و یکی از رکوردهای MIT-BIH یا فایل CSV خود را تحلیل کنید تا نوار زنده، کالبدشکافی ضربان و نمودار R-R فعال شوند.'
      : 'Select a bundled MIT-BIH recording or import a CSV from Monitor to unlock live playback, Beat X-Ray, and R-R Poincaré telemetry.';
  String get goToMonitor => isFa ? 'رفتن به مانیتور' : 'Open Monitor';

  String get beatsAnalyzed => isFa ? 'ضربان‌های تحلیل‌شده' : 'Beats analyzed';
  String get heartRate => isFa ? 'ضربان قلب' : 'Heart rate';
  String get bpmUnit => isFa ? 'ضربان/دقیقه' : 'bpm';
  String bpmValue(int? bpm) =>
      bpm == null ? '—' : (isFa ? '$bpm ضربان/دقیقه' : '$bpm bpm');
  String get durationLabel => isFa ? 'مدت نوار' : 'Duration';
  String get normalRatioLabel => isFa ? 'نسبت طبیعی' : 'Normal N';
  String get ectopicRatioLabel => isFa ? 'اکتوپیک S+V' : 'Ectopic S+V';
  String get sBeats => isFa ? 'ضربان‌های S' : 'S beats';
  String get vBeats => isFa ? 'ضربان‌های V' : 'V beats';
  String get nBeats => isFa ? 'ضربان‌های N' : 'N beats';

  // Studio ECG Cockpit & Playback
  String get ecgSignal => isFa ? 'مانیتور سیگنال ECG' : 'ECG Telemetry Strip';
  String windowLabel(int s) => isFa ? 'پنجره $s ثانیه‌ای' : '$s s window';
  String get play => isFa ? 'پخش زنده' : 'Play';
  String get pause => isFa ? 'توقف' : 'Pause';
  String get prevAbnormal => isFa ? 'S/V قبلی' : 'Prev S/V';
  String get nextAbnormal => isFa ? 'S/V بعدی' : 'Next S/V';
  String get fullscreenTooltip => isFa ? 'نمایش تمام‌صفحه' : 'Fullscreen Monitor';
  String get exitFullscreenTooltip =>
      isFa ? 'بستن نمای تمام‌صفحه' : 'Exit Fullscreen';
  String get copySummaryTooltip =>
      isFa ? 'کپی خلاصه تحلیل' : 'Copy educational summary';
  String get summaryCopied =>
      isFa ? 'خلاصه تحلیل در حافظه کپی شد.' : 'Educational summary copied to clipboard.';
  String beatNumberTime(int number, String time) =>
      isFa ? 'ضربان #$number · $time' : 'Beat #$number · $time';

  // Sub-Studio Tabs
  String get subTabTimeline => isFa ? 'خط زمانی' : 'Timeline';
  String get subTabXRay => isFa ? 'کالبدشکافی ضربان' : 'Beat X-Ray';
  String get subTabRhythm => isFa ? 'ریتم R-R' : 'R-R Rhythm';

  // Timeline sub-tab
  String get filterAbnormal => isFa ? 'غیرطبیعی (S/V)' : 'Abnormal (S/V)';
  String get filterAll => isFa ? 'همه' : 'All';
  String get inspectBeat => isFa ? 'کالبدشکافی' : 'X-Ray';
  String get beatCounts => isFa ? 'توزیع رده‌ها' : 'Beat breakdown';
  String get sAndVBeats => isFa ? 'ضربان‌های S و V' : 'S and V beats';
  String get calmNoArrhythmiaTitle => isFa
      ? 'ریتم آرام — موردی از S یا V شناسایی نشد'
      : 'Clean Sinus Strip — 0 S/V Beats Flagged';
  String get noArrhythmiaDetected => isFa ? 'موردی در این سیگنال شناسایی نشد.' : 'None detected in this signal.';
  String get tapToJump => isFa
      ? 'برای پرش به هر ضربان در نوار یا مشاهده در X-Ray روی آن لمس کنید.'
      : 'Tap a beat to center it on the strip, or open X-Ray.';

  // Beat X-Ray sub-tab
  String get xRayTitle => isFa ? 'میکروسکوپ ۲۰۰ نمونه‌ای ضربان' : '200-Sample Morphology X-Ray';
  String get selectedBeatLegend => isFa ? 'ضربان انتخاب‌شده' : 'Selected beat';
  String get medianTemplateLegend =>
      isFa ? 'الگوی میانه ثبت (شبح)' : 'Median template (ghost)';
  String get prevRrLabel => isFa ? 'R-R قبلی' : 'Prev R-R';
  String get nextRrLabel => isFa ? 'R-R بعدی' : 'Next R-R';
  String get vsMedianRrLabel => isFa ? 'نسبت به میانه' : 'vs Median';
  String get timestampLabel => isFa ? 'زمان' : 'Time';
  String get modelScoreHeading => isFa
      ? 'امتیاز وزن‌دار و احتمال خام مدل'
      : 'Decision Score & Raw Probability';
  String get weightedScoreCol => isFa ? 'score وزن‌دار' : 'Weighted score';
  String get rawProbCol => isFa ? 'احتمال خام' : 'Raw p';
  String get uncalibratedScoreNote => isFa
      ? 'تذکر: score نمایشی از ضرب احتمال خام در وزن [1.0, 0.25, 0.5, 0.0] نرمال می‌شود و یک شاخص نسبی و غیرکالیبره است — احتمال بالینی کالیبره‌شده نیست.'
      : 'Note: displayed score is normalized from proba * [1.0, 0.25, 0.5, 0.0]; it is a relative, uncalibrated ranking score, not a calibrated clinical probability.';
  String get partialWindowNote => isFa
      ? 'این ضربان نزدیک لبه سیگنال است و پنجره کامل ۲۰۰ نمونه‌ای ندارد.'
      : 'Boundary beat: full 200-sample morphology window unavailable.';

  // R-R Rhythm sub-tab
  String get medianRrLabel => isFa ? 'میانه R-R' : 'Median R-R';
  String get rrRangeLabel => isFa ? 'بازه R-R' : 'R-R Range';
  String get ectopicBurdenLabel => isFa ? 'بار اکتوپیک' : 'Ectopic burden';
  String get tachogramTitle => isFa ? 'تاکوگرام ضربان‌به‌ضربان R-R' : 'Beat-to-Beat R-R Tachogram';
  String get poincareTitle =>
      isFa ? 'نمودار پوانکاره (RR[n] در برابر RR[n+1])' : 'Poincaré HRV Plot (RR[n] vs RR[n+1])';
  String get tapRhythmHint => isFa
      ? 'با لمس هر نقطه، ضربان متناظر روی نوار انتخاب می‌شود.'
      : 'Tap any point to jump directly to that beat.';
  String get needMoreBeatsForRhythm => isFa
      ? 'برای نمایش تاکوگرام و پوانکاره حداقل ۳ ضربان تحلیل‌شده نیاز است.'
      : 'At least 3 analyzed beats are needed for Tachogram and Poincaré plots.';

  // Lab & Info Tab
  String get aboutTooltip => isFa ? 'آزمایشگاه و اطلاعات' : 'Lab & Info';
  String get aboutTitle => isFa ? 'آزمایشگاه و اطلاعات مدل' : 'BioVanta Lab & Model';
  String get aboutHeadline =>
      isFa ? 'طبقه‌بندی ضربان قلب BioVanta ECG' : 'BioVanta ECG Instrument';
  String get aboutTagline => isFa
      ? 'طبقه‌بندی بین‌بیماری تک‌لید ضربان قلب، کاملاً آفلاین روی گوشی.'
      : 'Inter-patient single-lead heartbeat classifier, 100% on-device.';

  String get pipelineTitle => isFa ? 'معماری ۳ مرحله‌ای پردازش' : '3-Stage On-Device Pipeline';
  String get stage1Title => '360 Hz DSP';
  String get stage1Sub => isFa
      ? 'فیلتر ضداشباه + باترورث ۰.۵–۴۰ هرتز + Pan–Tompkins'
      : '150 Hz AA + 0.5–40 Hz Butterworth + Pan–Tompkins';
  String get stage2Title => isFa ? '۸۴ ویژگی' : '84 Features';
  String get stage2Sub => isFa
      ? 'شکل‌شناسی مقیاس‌ناوردا + همبستگی با الگوی میانه'
      : 'Scale-invariant morphology + recording template';
  String get stage3Title => '163 KB HGB';
  String get stage3Sub => isFa
      ? 'مدل تقویت گرادیان آفلاین با دقت ریاضی ۶۴ بیتی'
      : 'Offline HistGradientBoosting · IEEE-754 float64';

  String get dataSectionTitle => isFa ? 'پایگاه‌های داده و تقسیم‌بندی' : 'Datasets & Evaluation';
  String get dataDesc1 => isFa
      ? 'پایگاه داده آریتمی MIT-BIH (PhysioNet): شامل ۴۸ رکورد نیم‌ساعته دو لید با فرکانس ۳۶۰ هرتز همراه با برچسب‌گذاری متخصصان (فقط لید MLII).'
      : 'MIT-BIH Arrhythmia Database (PhysioNet): 48 half-hour two-lead recordings at 360 Hz with expert beat annotations (lead MLII only).';
  String get dataDesc2 => isFa
      ? 'تفکیک بین‌بیماری (Inter-patient): ۲۲ بیمار در DS1 برای آموزش و ۲۲ بیمار کاملاً مجزا در DS2 برای آزمون، به‌همراه ارزیابی بین‌پایگاهی روی ۷۸ رکورد SVDB بدون بازآموزی.'
      : 'Inter-patient de Chazal split: 22 patients for DS1 training and 22 completely unseen patients for DS2 testing, plus zero-retraining transfer on 78 SVDB records.';

  String get testResultsTitle => isFa ? 'بنچمارک‌های تأییدشده' : 'Verified Benchmarks';
  String get ds2Subtitle => isFa ? 'MIT-BIH DS2 · ۲۲ بیمار دیده‌نشده' : 'MIT-BIH DS2 · 22 unseen patients';
  String get svdbSubtitle =>
      isFa ? 'SVDB · ۷۸ رکورد بدون بازآموزی' : 'SVDB Transfer · 78 records (zero retraining)';

  String get labelNF1 => isFa ? 'امتیاز F1 ضربان N' : 'N F1';
  String get labelVF1 => isFa ? 'امتیاز F1 ضربان V' : 'V F1';
  String get labelSF1 => isFa ? 'امتیاز F1 ضربان S' : 'S F1';
  String get labelMacroF1 => isFa ? 'میانگین کلی Macro F1 (N, S, V)' : 'Macro F1 (N, S, V)';
  String get labelAccuracy => isFa ? 'دقت کل (Accuracy)' : 'Accuracy';

  String get limitationsTitle => isFa ? 'محدودیت‌های بالینی و فنی' : 'Clinical & Technical Limits';
  String get limitationS => isFa
      ? 'ضربان‌های S ضعیف‌ترند (F1 کل ۰.۱۷۹ و روی ۲۱ بیمار بدون رکورد ۲۳۲ برابر ۰.۴۰۷): از نظر شکل موج بسیار شبیه ضربان‌های نرمال بوده و عمدتاً در زمان‌بندی و موج P تفاوت دارند.'
      : 'S beats are weak overall (F1 0.179 across DS2; 0.407 excluding outlier record 232): they resemble normal QRS beats and differ mostly in subtle timing and P-wave morphology.';
  String get limitationSustainedAtrial => isFa
      ? 'در ریتم‌های دهلیزی مداوم که اکثر ضربان‌های نوار غیرطبیعی‌اند (مانند رکورد ۲۳۲)، الگوی میانه بیمار و ریتم محلی با خود ریتم غیرطبیعی تنظیم می‌شوند و حساسیت S کاهش می‌یابد.'
      : 'In sustained ectopic atrial rhythms where most beats in the strip are abnormal (such as MIT-BIH record 232), the recording-median template and local rhythm adapt to the abnormal rhythm, reducing S recall.';
  String get limitationF => isFa
      ? 'ضربان‌های ترکیبی یا فیوژن (F) دارای وزن صفر هستند و توسط مدل پیش‌بینی نمی‌شوند.'
      : 'Fusion (F) beats carry weight 0 and are intentionally not predicted.';
  String get limitationSingleLead => isFa
      ? 'فقط تک‌لید و ارزیابی‌شده روی پایگاه‌های داده پژوهشی (MIT-BIH و SVDB)؛ بر روی سایر دستگاه‌ها یا جوامع بالینی اعتبارسنجی نشده است.'
      : 'Single lead only, evaluated on research databases (MIT-BIH and SVDB). Not validated on clinical populations or consumer wearables.';

  String get disclaimer => isFa
      ? 'نرم‌افزار پژوهشی و غیربالینی — دستگاه پزشکی دارای تأییدیه نیست و برای تشخیص بالینی یا تصمیم‌گیری درمانی طراحی نشده است.'
      : 'Research and non-clinical software — not a certified medical device and not intended for clinical diagnosis or treatment decisions.';

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

  String sampleBadge(String id) {
    switch (id) {
      case '200':
        return isFa ? 'بطنی (V)' : 'Ventricular';
      case '233':
        return isFa ? 'مختلط S+V' : 'Mixed S+V';
      case '100':
        return isFa ? 'سینوسی (N)' : 'Normal Sinus';
      default:
        return 'MIT-BIH';
    }
  }

  String sampleSubtitle(String id, String defaultSubtitle) {
    if (!isFa) return defaultSubtitle;
    switch (id) {
      case '200':
        return '۶۰ ثانیه · ۳۶۰ هرتز · چندین ضربان بطنی (V)';
      case '100':
        return '۶۰ ثانیه · ۳۶۰ هرتز · ریتم طبیعی و منظم (N)';
      case '233':
        return '۶۰ ثانیه · ۳۶۰ هرتز · ریتم آریتمی مختلط';
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
}
