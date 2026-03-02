import 'package:flutter/material.dart';
import 'package:my_first_app/core/utils/problem_a_lms_service.dart';
import 'package:my_first_app/core/utils/problem_a_risk_engine.dart';
import 'package:my_first_app/screens/problem_a_risk_review_screen.dart';
import 'package:my_first_app/services/api_service.dart';
import 'package:my_first_app/services/auth_service.dart';

class NutritionScreen extends StatefulWidget {
  final String childId;
  final String awwId;
  final int ageMonths;
  final String genderLabel;
  final String genderCode;
  final String awcCode;
  final String overallRisk;
  final String autismRisk;
  final String adhdRisk;
  final String behaviorRisk;
  final Map<String, double> domainScores;
  final Map<String, String>? domainRiskLevels;
  final int missedMilestones;
  final String explainability;
  final Map<String, int>? delaySummary;

  const NutritionScreen({
    super.key,
    required this.childId,
    required this.awwId,
    required this.ageMonths,
    required this.genderLabel,
    required this.genderCode,
    required this.awcCode,
    required this.overallRisk,
    required this.autismRisk,
    required this.adhdRisk,
    required this.behaviorRisk,
    required this.domainScores,
    required this.domainRiskLevels,
    required this.missedMilestones,
    required this.explainability,
    required this.delaySummary,
  });

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionRange {
  final double minWeight;
  final double maxWeight;
  final double minHeight;
  final double maxHeight;
  final double minMuac;
  final double maxMuac;
  final double minHb;
  final double maxHb;

  const _NutritionRange({
    required this.minWeight,
    required this.maxWeight,
    required this.minHeight,
    required this.maxHeight,
    required this.minMuac,
    required this.maxMuac,
    required this.minHb,
    required this.maxHb,
  });
}

class _NutritionAssessment {
  final double? waz;
  final double? haz;
  final double? whz;
  final bool underweight;
  final bool stunted;
  final bool wasted;
  final bool severeWasted;
  final bool anemia;
  final int score;
  final String risk;

  const _NutritionAssessment({
    required this.waz,
    required this.haz,
    required this.whz,
    required this.underweight,
    required this.stunted,
    required this.wasted,
    required this.severeWasted,
    required this.anemia,
    required this.score,
    required this.risk,
  });
}

class _NutritionScreenState extends State<NutritionScreen> {
  static const String _fleshFoodGroupKey = 'Flesh foods (meat/fish/poultry/organs)';
  static const String _eggFoodGroupKey = 'Eggs';
  final APIService _apiService = APIService();
  final AuthService _authService = AuthService();
  bool _isSubmitting = false;

  final TextEditingController _birthWeightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _muacController = TextEditingController();
  final TextEditingController _headCircumferenceController = TextEditingController();
  final TextEditingController _hemoglobinController = TextEditingController();
  final TextEditingController _sweetBeveragePerWeekController = TextEditingController();
  final TextEditingController _screenTimeHoursController = TextEditingController();
  final TextEditingController _physicalActivityMinutesController = TextEditingController();

  // Section 3: feeding practice fields (month-wise)
  bool _currentlyBreastfed = true;

  // 0-5 months
  bool _exclusiveBreastfeeding = true;
  bool _breastfeedingWithinOneHour = true;
  final TextEditingController _feedingFrequencyController = TextEditingController();
  bool _formulaMilkGiven = false;
  bool _waterGiven = false;
  bool _bottleFeeding = false;
  String? _breastfeedingFrequencyBand;
  bool _cowBuffaloMilkGiven = false;
  bool _honeyGiven = false;
  bool _ghuttiGiven = false;
  bool _otherFeedGiven = false;
  bool _nightFeedingPresent = true;
  String? _feedingDifficulty0to3;
  String? _feedingDifficulty3to6;

  // 6-23 months
  bool _introSolidSemiSoft = true; // ISSSF (6-8 months)
  final TextEditingController _solidFeedsPerDayController = TextEditingController(); // Q8 proxy
  final TextEditingController _milkFeedsPerDayController = TextEditingController(); // MMFF proxy
  bool _snacksGiven = true;
  String? _ageAtComplementaryStart;
  String? _mealFrequencyBand;
  String? _snacksPerDayBand;
  String? _feedingAssistance;
  bool _animalSourceFoodsConsumed = false;
  String? _foodConsistency;
  bool _selfFeedingAttempts = false;
  String? _milkIntakeType;
  String? _feedingBehavior;
  String? _junkFoodBand;
  String? _sweetDrinksBand;
  String? _screenTimeBand;
  String? _physicalActivityBand;
  final Map<String, bool> _iycfFoodGroups = <String, bool>{
    'Grains, roots, tubers, plantains': false,
    'Beans, peas, lentils, nuts, seeds': false,
    'Dairy products': false,
    _fleshFoodGroupKey: false,
    _eggFoodGroupKey: false,
    'Vitamin A-rich fruits/vegetables': false,
    'Other fruits/vegetables': false,
  };

  // 24-72 months
  final TextEditingController _mealsPerDayController = TextEditingController();
  final TextEditingController _milkIntakeMlController = TextEditingController();
  final TextEditingController _eggPerWeekController = TextEditingController();
  final TextEditingController _fruitPerWeekController = TextEditingController();
  final TextEditingController _greensPerWeekController = TextEditingController();
  final TextEditingController _junkFoodPerWeekController = TextEditingController();
  final bool _bilateralEdema = false;
  bool _repeatedIllness = false;

  // Section 1
  bool _recentIllness = false;
  final bool _prematureBirth = false;
  String? _appetiteStatus;
  final bool _attendsAwcOrSchool = false;

  // Section 4
  bool _ironSupplementation = false;
  bool _vitaminADose = false;
  bool _dewormingLastSixMonths = false;
  bool _immunizationUpToDate = true;
  bool _vitaminKGivenAtBirth = false;
  bool _vitaminDSupplementation = false;

  // Section 5
  bool _frequentDiarrhea = false;
  bool _poorAppetite = false;
  bool _swellingFeet = false;
  bool _lethargic = false;
  bool _poorWeightGain = false;
  bool _fever = false;
  bool _vomiting = false;
  bool _persistentVomiting = false;
  bool _convulsions = false;
  bool _recurrentRespiratoryInfections = false;
  bool _weightLossRecently = false;
  bool _feedingDifficultySymptom = false;
  bool _lowEnergy = false;
  bool _lowActivityLevel = false;

  @override
  void initState() {
    super.initState();
    _ensureLmsReady();
  }

  Future<void> _ensureLmsReady() async {
    try {
      await ProblemALmsService.instance.initialize();
    } catch (_) {
      // Keep graceful fallback if LMS assets fail to load.
    }
  }

  @override
  void dispose() {
    _birthWeightController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _muacController.dispose();
    _headCircumferenceController.dispose();
    _hemoglobinController.dispose();
    _sweetBeveragePerWeekController.dispose();
    _screenTimeHoursController.dispose();
    _physicalActivityMinutesController.dispose();
    _feedingFrequencyController.dispose();
    _solidFeedsPerDayController.dispose();
    _milkFeedsPerDayController.dispose();
    _mealsPerDayController.dispose();
    _milkIntakeMlController.dispose();
    _eggPerWeekController.dispose();
    _fruitPerWeekController.dispose();
    _greensPerWeekController.dispose();
    _junkFoodPerWeekController.dispose();
    super.dispose();
  }

  _NutritionRange _rangeForAge(int ageMonths) {
    if (ageMonths <= 3) {
      return const _NutritionRange(minWeight: 5.0, maxWeight: 6.0, minHeight: 57, maxHeight: 61, minMuac: 13.0, maxMuac: 13.8, minHb: 14, maxHb: 20);
    }
    if (ageMonths <= 6) {
      return const _NutritionRange(minWeight: 6.0, maxWeight: 7.5, minHeight: 61, maxHeight: 66, minMuac: 13.5, maxMuac: 14.5, minHb: 11, maxHb: 14);
    }
    if (ageMonths <= 9) {
      return const _NutritionRange(minWeight: 7.0, maxWeight: 8.5, minHeight: 66, maxHeight: 71, minMuac: 14.0, maxMuac: 15.0, minHb: 11, maxHb: 13);
    }
    if (ageMonths <= 12) {
      return const _NutritionRange(minWeight: 8.0, maxWeight: 9.5, minHeight: 70, maxHeight: 75, minMuac: 14.5, maxMuac: 15.5, minHb: 11, maxHb: 13);
    }
    if (ageMonths <= 18) {
      return const _NutritionRange(minWeight: 9.0, maxWeight: 11.0, minHeight: 75, maxHeight: 82, minMuac: 15.0, maxMuac: 16.0, minHb: 11, maxHb: 13);
    }
    if (ageMonths <= 24) {
      return const _NutritionRange(minWeight: 10.5, maxWeight: 12.5, minHeight: 82, maxHeight: 88, minMuac: 15.5, maxMuac: 16.5, minHb: 11, maxHb: 13);
    }
    if (ageMonths <= 36) {
      return const _NutritionRange(minWeight: 12.0, maxWeight: 14.5, minHeight: 88, maxHeight: 96, minMuac: 16.0, maxMuac: 17.0, minHb: 11, maxHb: 13);
    }
    if (ageMonths <= 48) {
      return const _NutritionRange(minWeight: 14.0, maxWeight: 17.0, minHeight: 96, maxHeight: 105, minMuac: 16.5, maxMuac: 17.5, minHb: 11, maxHb: 13.5);
    }
    if (ageMonths <= 60) {
      return const _NutritionRange(minWeight: 16.0, maxWeight: 20.0, minHeight: 105, maxHeight: 112, minMuac: 17.0, maxMuac: 18.0, minHb: 11.5, maxHb: 13.5);
    }
    return const _NutritionRange(minWeight: 18.0, maxWeight: 23.0, minHeight: 112, maxHeight: 120, minMuac: 17.5, maxMuac: 18.5, minHb: 11.5, maxHb: 14.0);
  }

  double? _toDouble(TextEditingController controller) {
    final raw = controller.text.trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  int? _toInt(TextEditingController controller) {
    final raw = controller.text.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  double? _bmi() {
    final weight = _toDouble(_weightController);
    final heightCm = _toDouble(_heightController);
    if (weight == null || heightCm == null || heightCm <= 0) return null;
    final heightM = heightCm / 100;
    return weight / (heightM * heightM);
  }

  String _bmiForAgeStatus() {
    final bmi = _bmi();
    if (bmi == null) return 'Pending input';
    if (bmi < 13.5) return 'Low';
    if (bmi > 18.5) return 'High';
    return 'Normal';
  }

  bool get _lowBirthWeightFlag {
    final bw = _toDouble(_birthWeightController);
    return bw != null && bw < 2.5;
  }

  int _boolInt(bool value) => value ? 1 : 0;

  Map<String, dynamic> _buildNutritionModelFeatures(_NutritionRange range) {
    final assessment = _computeNutritionAssessment(range);
    final features = <String, dynamic>{
      'age_months': widget.ageMonths,
      'gender_code': widget.genderCode,
      'birth_weight_kg': _toDouble(_birthWeightController),
      'low_birth_weight': _boolInt(_lowBirthWeightFlag),
      'recent_illness': _boolInt(_recentIllness),
      'weight_kg': _toDouble(_weightController),
      'height_cm': _toDouble(_heightController),
      'muac_cm': _toDouble(_muacController),
      'hemoglobin_gdl': _toDouble(_hemoglobinController),
      'waz': assessment.waz,
      'haz': assessment.haz,
      'whz': assessment.whz,
      'underweight': _boolInt(assessment.underweight),
      'stunting': _boolInt(assessment.stunted),
      'wasting': _boolInt(assessment.wasted),
      'anemia': _boolInt(assessment.anemia),
      'rule_nutrition_score': assessment.score,
      'rule_nutrition_risk': assessment.risk,
      'rule_referral_required': _boolInt(_referralRequired(range)),
    };
    features.removeWhere((_, value) => value == null || (value is String && value.trim().isEmpty));
    return features;
  }

  bool get _isAge0to3Months => widget.ageMonths >= 0 && widget.ageMonths < 3;
  bool get _isAge3to6Months => widget.ageMonths >= 3 && widget.ageMonths < 6;
  bool get _isAge6to9Months => widget.ageMonths >= 6 && widget.ageMonths < 9;
  bool get _isAge9to12Months => widget.ageMonths >= 9 && widget.ageMonths < 12;
  bool get _isAge12to24Months => widget.ageMonths >= 12 && widget.ageMonths < 24;
  bool get _isAge24to36Months => widget.ageMonths >= 24 && widget.ageMonths < 36;
  bool get _isAge36to48Months => widget.ageMonths >= 36 && widget.ageMonths < 48;
  bool get _isAge48to60Months => widget.ageMonths >= 48 && widget.ageMonths < 60;
  bool get _isAge36to60Months => widget.ageMonths >= 36 && widget.ageMonths < 60;
  bool get _isAge60to72Months => widget.ageMonths >= 60 && widget.ageMonths <= 72;

  bool get _isAge0to5Months => widget.ageMonths >= 0 && widget.ageMonths < 6;
  bool get _isAge6to23Months => widget.ageMonths >= 6 && widget.ageMonths < 24;
  bool get _isAge6to8Months => widget.ageMonths >= 6 && widget.ageMonths < 9;
  bool get _isAge24to72Months => widget.ageMonths >= 24 && widget.ageMonths <= 72;
  bool get _requiresHemoglobin => widget.ageMonths >= 3;
  bool get _showMicronutrientsSection => true;

  String _weightForAgeStatus(_NutritionRange range) {
    final weight = _toDouble(_weightController);
    if (weight == null) return 'Pending input';
    if (weight < range.minWeight * 0.85) return 'Severely underweight';
    if (weight < range.minWeight) return 'Underweight';
    if (weight > range.maxWeight * 1.2) return 'High for age';
    return 'Normal';
  }

  String _heightForAgeStatus(_NutritionRange range) {
    final height = _toDouble(_heightController);
    if (height == null) return 'Pending input';
    if (height < range.minHeight * 0.9) return 'Severe stunting';
    if (height < range.minHeight) return 'Stunting risk';
    return 'Normal';
  }

  String _weightForHeightStatus(_NutritionRange range) {
    final weight = _toDouble(_weightController);
    final height = _toDouble(_heightController);
    if (weight == null || height == null) return 'Pending input';

    final avgWeight = (range.minWeight + range.maxWeight) / 2;
    final avgHeight = (range.minHeight + range.maxHeight) / 2;
    final expectedWeight = avgWeight * (height / avgHeight);
    if (weight < expectedWeight * 0.8) return 'Wasting risk';
    if (weight > expectedWeight * 1.2) return 'High weight-for-height';
    return 'Normal';
  }

  String _muacRisk(_NutritionRange range) {
    final muac = _toDouble(_muacController);
    if (muac == null) return 'Pending input';
    if (muac < 11.5) return 'Severe acute malnutrition';
    if (muac < 12.5) return 'Moderate acute malnutrition';
    if (muac < range.minMuac) return 'At risk';
    return 'Normal';
  }

  String _anemiaRisk(_NutritionRange range) {
    final hb = _toDouble(_hemoglobinController);
    if (hb == null) return 'Pending input';
    if (hb < 7) return 'Severe anemia';
    if (hb < 11) return 'Moderate anemia';
    if (hb < range.minHb) return 'Mild anemia';
    return 'Normal';
  }

  int _statusScore(String status) {
    final s = status.toLowerCase();
    if (s.contains('severe')) return 3;
    if (s.contains('moderate')) return 2;
    if (s.contains('risk') || s.contains('underweight') || s.contains('mild') || s.contains('high')) return 1;
    return 0;
  }

  int _mddFoodGroupScore() {
    if (!_isAge6to23Months) return 0;
    var score = 0;
    if (_currentlyBreastfed) score += 1; // WHO MDD group #1: breast milk
    for (final group in _visibleIycfFoodGroups()) {
      final selected = _iycfFoodGroups[group] ?? false;
      if (selected) score += 1;
    }
    return score;
  }

  bool _mddAchieved() {
    if (!_isAge6to23Months) return false;
    return _mddFoodGroupScore() >= 5;
  }

  bool _mmfAchieved() {
    if (!_isAge6to23Months) return false;
    final solidFeeds = _mealCountProxyFor6to23();
    final milkFeeds = _toInt(_milkFeedsPerDayController) ?? 0;
    if (_currentlyBreastfed) {
      if (_isAge6to8Months) return solidFeeds >= 2;
      return solidFeeds >= 3; // 9-23 months
    }
    final totalFeeds = solidFeeds + milkFeeds;
    return totalFeeds >= 4 && solidFeeds >= 1;
  }

  bool _mmffAchieved() {
    if (!_isAge6to23Months || _currentlyBreastfed) return false;
    final milkFeeds = _toInt(_milkFeedsPerDayController) ?? 0;
    return milkFeeds >= 2;
  }

  bool _madAchieved() {
    if (!_isAge6to23Months) return false;
    if (!_mddAchieved() || !_mmfAchieved()) return false;
    return _currentlyBreastfed || _mmffAchieved();
  }

  bool _effAchieved() {
    if (!_isAge6to23Months) return false;
    return (_iycfFoodGroups[_fleshFoodGroupKey] ?? false) || (_iycfFoodGroups[_eggFoodGroupKey] ?? false);
  }

  bool _zvfFlag() {
    if (!_isAge6to23Months) return false;
    final vitA = _iycfFoodGroups['Vitamin A-rich fruits/vegetables'] ?? false;
    final other = _iycfFoodGroups['Other fruits/vegetables'] ?? false;
    return !vitA && !other;
  }

  List<String> _visibleIycfFoodGroups() {
    if (!_isAge6to23Months) return const <String>[];
    return _iycfFoodGroups.keys.toList();
  }

  bool _exclusiveBreastfeedingUnder6Achieved() {
    if (!_isAge0to5Months) return false;
    return _currentlyBreastfed &&
        _exclusiveBreastfeeding &&
        !_formulaMilkGiven &&
        !_cowBuffaloMilkGiven &&
        !_waterGiven &&
        !_honeyGiven &&
        !_ghuttiGiven &&
        !_otherFeedGiven;
  }

  bool _isssfAchieved() {
    if (!_isAge6to8Months) return false;
    final solids = _mealCountProxyFor6to23();
    return _introSolidSemiSoft || solids >= 1;
  }

  int _mealCountProxyFor6to23() {
    switch (_mealFrequencyBand) {
      case '0-1':
        return 1;
      case '0-2':
        return 2;
      case '2':
        return 2;
      case '3':
        return 3;
      case '3 or more':
        return 3;
      case '4 or more':
        return 4;
      default:
        return _toInt(_solidFeedsPerDayController) ?? 0;
    }
  }

  int _feedingRiskScore() {
    var score = 0;
    if (_isAge0to5Months) {
      if (!_exclusiveBreastfeedingUnder6Achieved()) score += 3;
      if (!_breastfeedingWithinOneHour) score += 1;
      if (_formulaMilkGiven) score += 1;
      if (_waterGiven) score += 1;
      if (_cowBuffaloMilkGiven) score += 1;
      if (_honeyGiven || _ghuttiGiven || _otherFeedGiven) score += 2;
      if (_bottleFeeding) score += 1;
      if (_breastfeedingFrequencyBand == '< 8 times') score += 1;
      if (_isAge3to6Months && !_nightFeedingPresent) score += 1;
    } else if (_isAge6to23Months) {
      if (_isAge6to8Months && !_isssfAchieved()) score += 2;
      if (!_mddAchieved()) score += 2;
      if (!_mmfAchieved()) score += 2;
      if (!_currentlyBreastfed && !_mmffAchieved()) score += 1;
      if (!_madAchieved()) score += 2;
      if (!_isAge6to8Months && !_effAchieved()) score += 1;
      if (_isAge6to9Months && _ageAtComplementaryStart != null && _ageAtComplementaryStart != '6 months') score += 1;
      if (_isAge9to12Months && _foodConsistency == 'Thin liquid') score += 1;
      if (_isAge9to12Months && !_animalSourceFoodsConsumed) score += 1;
      if (_zvfFlag()) score += 1;
      if (_isAge12to24Months) {
        final milkMl = _toInt(_milkIntakeMlController);
        if (milkMl != null && milkMl < 250) score += 1;
        final eggs = _toInt(_eggPerWeekController);
        if (eggs != null && eggs < 2) score += 1;
        final fruits = _toInt(_fruitPerWeekController);
        if (fruits != null && fruits < 4) score += 1;
        final greens = _toInt(_greensPerWeekController);
        if (greens != null && greens < 3) score += 1;
        final junk = _toInt(_junkFoodPerWeekController);
        if (junk != null && junk > 3) score += 1;
        final sweet = _toInt(_sweetBeveragePerWeekController);
        if (sweet != null && sweet > 3) score += 1;
        if (!_animalSourceFoodsConsumed) score += 1;
        if (_feedingBehavior == 'Refuses food often' || _feedingBehavior == 'Forced feeding') score += 1;
      }
    } else {
      if (_mealFrequencyBand == '<3') score += 1;
      final milkMl = _toInt(_milkIntakeMlController);
      if (milkMl != null && milkMl < 250) score += 1;
      final eggs = _toInt(_eggPerWeekController);
      if (eggs != null && eggs < 3) score += 1;
      final fruits = _toInt(_fruitPerWeekController);
      if (fruits != null && fruits < 4) score += 1;
      final greens = _toInt(_greensPerWeekController);
      if (greens != null && greens < 3) score += 1;
      final junk = _toInt(_junkFoodPerWeekController);
      if (junk != null && junk > 3) score += 2;
      final sweet = _toInt(_sweetBeveragePerWeekController);
      if (sweet != null && sweet > 3) score += 1;
      final selectedGroups = _iycfFoodGroups.values.where((v) => v).length;
      if (selectedGroups > 0 && selectedGroups < 4) score += 1;
      if (!_animalSourceFoodsConsumed) score += 1;
      if (_junkFoodBand == '3 or more times') score += 1;
      if (_sweetDrinksBand == 'Daily') score += 1;
    }
    return score;
  }

  int _riskSymptomScore() {
    var score = 0;
    if (_frequentDiarrhea) score += 1;
    if (_poorAppetite) score += 1;
    if (_swellingFeet) score += 2;
    if (_lethargic) score += 2;
    return score;
  }

  int _micronutrientScore() {
    var score = 0;
    if (!_immunizationUpToDate) score += 1;
    if (_isAge0to3Months && !_vitaminKGivenAtBirth) score += 1;
    if (_isAge3to6Months && !_vitaminDSupplementation) score += 1;
    if (widget.ageMonths >= 12 && widget.ageMonths < 36 && !_ironSupplementation) score += 1;
    if (widget.ageMonths >= 6 && widget.ageMonths < 60 && !_vitaminADose) score += 1;
    if (widget.ageMonths >= 12 && !_dewormingLastSixMonths) score += 1;
    return score;
  }

  _NutritionAssessment _computeNutritionAssessment(_NutritionRange range) {
    final weight = _toDouble(_weightController);
    final height = _toDouble(_heightController);
    final hb = _toDouble(_hemoglobinController);

    final lms = ProblemALmsService.instance;
    final wfaLms = lms.wfaByAgeMonths(
      ageMonths: widget.ageMonths,
      genderCode: widget.genderCode,
    );
    final hfaLms = lms.hfaByAgeMonths(
      ageMonths: widget.ageMonths,
      genderCode: widget.genderCode,
    );
    final wfhLms = (height == null || height <= 0)
        ? null
        : lms.wfhByHeightCm(
            heightCm: height,
            genderCode: widget.genderCode,
          );

    final waz = (weight != null && weight > 0 && wfaLms != null)
        ? lms.zScore(x: weight, point: wfaLms)
        : null;
    final haz = (height != null && height > 0 && hfaLms != null)
        ? lms.zScore(x: height, point: hfaLms)
        : null;
    final whz = (weight != null && weight > 0 && wfhLms != null)
        ? lms.zScore(x: weight, point: wfhLms)
        : null;

    final underweight = waz == null
        ? (weight != null && weight < range.minWeight)
        : (waz < -2);
    final stunted = haz == null
        ? (height != null && height < range.minHeight)
        : (haz < -2);
    final wasted = whz == null
        ? _weightForHeightStatus(range) == 'Wasting risk'
        : (whz < -2);
    final severeWasted = whz != null && whz < -3;
    final anemia = hb != null &&
        widget.ageMonths >= 6 &&
        widget.ageMonths <= 59 &&
        hb < 11.0;

    // Requested formula:
    // (Underweight*2) + (Stunting*3) + (Wasting*2) + (Anemia*1)
    final score = (underweight ? 2 : 0) +
        (stunted ? 3 : 0) +
        (wasted ? 2 : 0) +
        (anemia ? 1 : 0);
    final risk = score == 0
        ? 'Low'
        : (score <= 3 ? 'Medium' : 'High');

    return _NutritionAssessment(
      waz: waz,
      haz: haz,
      whz: whz,
      underweight: underweight,
      stunted: stunted,
      wasted: wasted,
      severeWasted: severeWasted,
      anemia: anemia,
      score: score,
      risk: risk,
    );
  }

  int _overallRiskScore(_NutritionRange range) {
    return _computeNutritionAssessment(range).score;
  }

  String _overallRiskLabel(_NutritionRange range) {
    return _computeNutritionAssessment(range).risk;
  }

  bool _referralRequired(_NutritionRange range) {
    final assessment = _computeNutritionAssessment(range);
    return assessment.severeWasted || assessment.score >= 4;
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD6E1EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _readOnlyField(String label, String value) {
    return TextFormField(
      enabled: false,
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _numberField(String label, TextEditingController controller, {String? helperText}) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _dropdownField({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
    String? helperText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          border: const OutlineInputBorder(),
        ),
        items: options
            .map(
              (opt) => DropdownMenuItem<String>(
                value: opt,
                child: Text(opt),
              ),
            )
            .toList(),
        onChanged: (v) {
          onChanged(v);
          setState(() {});
        },
      ),
    );
  }

  Widget _yesNoSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDCE7F2)),
      ),
      child: SwitchListTile(
        value: value,
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(value ? 'Yes' : 'No'),
        onChanged: (v) {
          onChanged(v);
          setState(() {});
        },
      ),
    );
  }

  String? _validateFeedingSection() {
    if (widget.ageMonths < 6) {
      final hc = _toDouble(_headCircumferenceController);
      if (hc == null || hc <= 0) {
        return 'Please enter head circumference (cm) for age below 6 months.';
      }
    }

    if (widget.ageMonths >= 6) {
      final muac = _toDouble(_muacController);
      if (muac == null || muac <= 0) {
        return 'Please enter MUAC (cm) for age 6 months and above.';
      }
    }

    if (_requiresHemoglobin && _toDouble(_hemoglobinController) == null) {
      return 'Please enter hemoglobin (g/dL) for age ${widget.ageMonths} months.';
    }

    if (_isAge0to5Months) {
      if (_breastfeedingFrequencyBand == null) {
        return 'Please select breastfeeding frequency (last 24 hours).';
      }
      if (!_exclusiveBreastfeeding &&
          !_formulaMilkGiven &&
          !_cowBuffaloMilkGiven &&
          !_waterGiven &&
          !_honeyGiven &&
          !_ghuttiGiven &&
          !_otherFeedGiven) {
        return 'Please select what is given when exclusive breastfeeding is No.';
      }
      if (_isAge0to3Months && _feedingDifficulty0to3 == null) {
        return 'Please select breastfeeding difficulty for age 0-3 months.';
      }
      if (_isAge3to6Months && _feedingDifficulty3to6 == null) {
        return 'Please select feeding difficulty for age 3-6 months.';
      }
    } else if (_isAge6to23Months) {
      if (_mealFrequencyBand == null) {
        return 'Please select meals per day (yesterday).';
      }
      if (_isAge6to9Months) {
        if (_ageAtComplementaryStart == null) {
          return 'Please select age at complementary feeding started.';
        }
        if (_feedingAssistance == null) {
          return 'Please select feeding assistance.';
        }
      }
      if (_isAge9to12Months) {
        if (_foodConsistency == null) {
          return 'Please select food consistency.';
        }
      }
      if (_isAge12to24Months) {
        if (_snacksPerDayBand == null) {
          return 'Please select snacks per day.';
        }
        if (_milkIntakeType == null) {
          return 'Please select milk intake type.';
        }
        if (_feedingBehavior == null) {
          return 'Please select feeding behavior.';
        }
      }
      if (_iycfFoodGroups.values.where((v) => v).isEmpty) {
        return 'Please select at least one food group consumed yesterday.';
      }
    } else if (_isAge24to72Months) {
      if (_mealFrequencyBand == null) {
        return 'Please select meals per day (yesterday).';
      }
      if (_snacksPerDayBand == null) {
        return 'Please select snacks per day.';
      }
      if (_junkFoodBand == null) {
        return 'Please select junk/processed food frequency.';
      }
      if (_sweetDrinksBand == null) {
        return 'Please select sugary drinks frequency.';
      }
      if (_isAge48to60Months || _isAge60to72Months) {
        if (_screenTimeBand == null) {
          return 'Please select screen time per day.';
        }
      }
      if (_isAge60to72Months && _physicalActivityBand == null) {
        return 'Please select physical activity per day.';
      }
      if (_iycfFoodGroups.values.where((v) => v).isEmpty) {
        return 'Please select at least one food group consumed yesterday.';
      }
    }
    return null;
  }

  Future<bool> _showNutritionResultTable({
    required _NutritionAssessment assessment,
  }) async {
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Nutrition Result Table'),
          content: SingleChildScrollView(
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Metric')),
                DataColumn(label: Text('Value')),
              ],
              rows: [
                DataRow(cells: [
                  const DataCell(Text('WAZ')),
                  DataCell(Text(assessment.waz?.toStringAsFixed(2) ?? 'N/A')),
                ]),
                DataRow(cells: [
                  const DataCell(Text('HAZ')),
                  DataCell(Text(assessment.haz?.toStringAsFixed(2) ?? 'N/A')),
                ]),
                DataRow(cells: [
                  const DataCell(Text('WHZ')),
                  DataCell(Text(assessment.whz?.toStringAsFixed(2) ?? 'N/A')),
                ]),
                DataRow(cells: [
                  const DataCell(Text('Underweight')),
                  DataCell(Text(assessment.underweight ? '1' : '0')),
                ]),
                DataRow(cells: [
                  const DataCell(Text('Stunting')),
                  DataCell(Text(assessment.stunted ? '1' : '0')),
                ]),
                DataRow(cells: [
                  const DataCell(Text('Wasting')),
                  DataCell(Text(assessment.wasted ? '1' : '0')),
                ]),
                DataRow(cells: [
                  const DataCell(Text('Anemia')),
                  DataCell(Text(assessment.anemia ? '1' : '0')),
                ]),
                DataRow(cells: [
                  const DataCell(Text('Nutrition Score')),
                  DataCell(Text('${assessment.score}')),
                ]),
                DataRow(cells: [
                  const DataCell(Text('Risk Category')),
                  DataCell(Text(assessment.risk)),
                ]),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
    return proceed ?? false;
  }

  Future<void> _continue() async {
    if (_isSubmitting) return;
    final range = _rangeForAge(widget.ageMonths);
    final birthWeight = _toDouble(_birthWeightController);
    final weight = _toDouble(_weightController);
    final height = _toDouble(_heightController);
    final muac = _toDouble(_muacController);
    final hb = _toDouble(_hemoglobinController);

    if (birthWeight == null ||
        birthWeight <= 0 ||
        weight == null ||
        weight <= 0 ||
        height == null ||
        height <= 0 ||
        muac == null ||
        muac <= 0 ||
        hb == null ||
        hb <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please fill required fields: Birth Weight, Weight, Height, MUAC, and Hemoglobin.',
          ),
        ),
      );
      return;
    }

    await _ensureLmsReady();
    final assessment = _computeNutritionAssessment(range);
    final referral = _referralRequired(range) ? 'Yes' : 'No';
    final localRisk = assessment.risk;

    if (!mounted) return;
    final shouldContinue = await _showNutritionResultTable(
      assessment: assessment,
    );
    if (!mounted) return;
    if (!shouldContinue) return;
    final submitAwcCode = await _resolveAwcCodeForSubmit();
    final submitAwwId = submitAwcCode.isNotEmpty ? submitAwcCode : widget.awwId.trim();
    if (!mounted) return;

    setState(() => _isSubmitting = true);
    try {
      await _apiService.submitNutritionResult(
        {
          'child_id': widget.childId,
          'awc_code': submitAwcCode,
          'aww_id': submitAwwId,
          'age_months': widget.ageMonths,
          'waz': assessment.waz,
          'haz': assessment.haz,
          'whz': assessment.whz,
          'underweight': assessment.underweight ? 1 : 0,
          'stunting': assessment.stunted ? 1 : 0,
          'wasting': assessment.wasted ? 1 : 0,
          'anemia': assessment.anemia ? 1 : 0,
          'nutrition_score': assessment.score,
          'risk_category': assessment.risk,
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save nutrition result: $e')),
        );
      }
      return;
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }

    final zPart = 'WAZ: ${assessment.waz?.toStringAsFixed(2) ?? "N/A"}, '
        'HAZ: ${assessment.haz?.toStringAsFixed(2) ?? "N/A"}, '
        'WHZ: ${assessment.whz?.toStringAsFixed(2) ?? "N/A"}';
    final flagsPart = 'Underweight=${assessment.underweight ? 1 : 0}, '
        'Stunting=${assessment.stunted ? 1 : 0}, '
        'Wasting=${assessment.wasted ? 1 : 0}, '
        'Anemia=${assessment.anemia ? 1 : 0}';
    final nutritionSummary =
        'Nutrition score: ${assessment.score} ($localRisk), '
        '$zPart, $flagsPart, referral required: $referral';
    final explainability = widget.explainability.trim().isEmpty
        ? nutritionSummary
        : '${widget.explainability}; $nutritionSummary';

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProblemARiskReviewScreen(
          childId: widget.childId,
          awwId: submitAwwId,
          ageMonths: widget.ageMonths,
          genderLabel: widget.genderLabel,
          genderCode: widget.genderCode,
          awcCode: submitAwcCode,
          overallRisk: widget.overallRisk,
          autismRisk: widget.autismRisk,
          adhdRisk: widget.adhdRisk,
          behaviorRisk: widget.behaviorRisk,
          weightKg: weight,
          heightCm: height,
          muacCm: muac,
          birthWeightKg: birthWeight,
          hemoglobin: hb,
          recentIllness: _recentIllness ? 'Yes' : 'No',
          domainScores: widget.domainScores,
          domainRiskLevels: widget.domainRiskLevels,
          missedMilestones: widget.missedMilestones,
          explainability: explainability,
          delaySummary: widget.delaySummary,
          environmentInput: const ProblemAEnvironmentInput(
            talksDaily: true,
            storyReading: false,
            playTimeAdequate: true,
            screenTimeHealthy: true,
            toysAvailable: true,
            safePlaySpace: true,
          ),
          immunizationStatus: 'unknown',
          congenitalDefect: false,
          hearingConcern: false,
          visionConcern: false,
        ),
      ),
    );
  }

  Future<String> _resolveAwcCodeForSubmit() async {
    final fromSession = (await _authService.getLoggedInAwcCode() ?? '')
        .trim()
        .toUpperCase();
    if (fromSession.isNotEmpty) return fromSession;

    final fromAww = widget.awwId.trim().toUpperCase();
    if (fromAww.isNotEmpty) return fromAww;

    return widget.awcCode.trim().toUpperCase();
  }

  Widget _buildFeedingPracticesSection() {
    if (_isAge0to5Months) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isAge0to3Months
                ? 'Breastfeeding-only stage: no solids, no diet diversity, no meal frequency scoring.'
                : 'Exclusive breastfeeding stage (3-6 months): no complementary feeding questions.',
            style: const TextStyle(color: Color(0xFF546E7A), fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 8),
          _yesNoSwitch('Currently breastfed? *', _currentlyBreastfed, (v) => _currentlyBreastfed = v),
          if (_isAge0to3Months)
            _yesNoSwitch(
              'Initiation of breastfeeding within 1 hour of birth?',
              _breastfeedingWithinOneHour,
              (v) => _breastfeedingWithinOneHour = v,
            ),
          _yesNoSwitch('Exclusive breastfeeding? *', _exclusiveBreastfeeding, (v) => _exclusiveBreastfeeding = v),
          if (!_exclusiveBreastfeeding) ...[
            const SizedBox(height: 4),
            const Text('If NOT exclusively breastfed, what is given?', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            _yesNoSwitch('Formula milk', _formulaMilkGiven, (v) => _formulaMilkGiven = v),
            _yesNoSwitch('Cow/buffalo milk', _cowBuffaloMilkGiven, (v) => _cowBuffaloMilkGiven = v),
            _yesNoSwitch('Water', _waterGiven, (v) => _waterGiven = v),
            _yesNoSwitch('Honey', _honeyGiven, (v) => _honeyGiven = v),
            _yesNoSwitch('Ghutti/traditional feeds', _ghuttiGiven, (v) => _ghuttiGiven = v),
            _yesNoSwitch('Other', _otherFeedGiven, (v) => _otherFeedGiven = v),
          ],
          _dropdownField(
            label: 'Breastfeeding frequency (last 24 hours) *',
            value: _breastfeedingFrequencyBand,
            options: const ['< 8 times', '8-12 times', '12 or more times'],
            onChanged: (v) => _breastfeedingFrequencyBand = v,
          ),
          if (_isAge3to6Months) _yesNoSwitch('Night feeding present?', _nightFeedingPresent, (v) => _nightFeedingPresent = v),
          _dropdownField(
            label: 'Any difficulty in breastfeeding?',
            value: _isAge0to3Months ? _feedingDifficulty0to3 : _feedingDifficulty3to6,
            options: _isAge0to3Months
                ? const ['Poor latch', 'Baby sleepy', 'Mother has pain', 'No issues']
                : const ['Poor latch', 'Baby refuses feeding', 'Vomiting', 'No difficulty'],
            onChanged: (v) {
              if (_isAge0to3Months) {
                _feedingDifficulty0to3 = v;
              } else {
                _feedingDifficulty3to6 = v;
              }
            },
          ),
          _yesNoSwitch('Bottle feeding in last 24 hours?', _bottleFeeding, (v) => _bottleFeeding = v),
        ],
      );
    }

    if (_isAge6to23Months) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isAge6to9Months
                ? 'Transition stage: breastfeeding continues and complementary feeding starts.'
                : (_isAge9to12Months
                    ? '9-12 months: diversity and consistency become critical.'
                    : '12-24 months: full family-diet pattern with meal + snack tracking.'),
            style: const TextStyle(color: Color(0xFF546E7A), fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 8),
          _yesNoSwitch('Currently breastfed? *', _currentlyBreastfed, (v) => _currentlyBreastfed = v),
          if (_isAge6to9Months) ...[
            _yesNoSwitch('Complementary feeding started? *', _introSolidSemiSoft, (v) => _introSolidSemiSoft = v),
            _dropdownField(
              label: 'Age at complementary feeding started? *',
              value: _ageAtComplementaryStart,
              options: const ['Earlier (<6 months)', '6 months', 'Later (>7 months)'],
              onChanged: (v) => _ageAtComplementaryStart = v,
            ),
            _dropdownField(
              label: 'Meals per day (yesterday) *',
              value: _mealFrequencyBand,
              options: const ['0-1', '2', '3 or more'],
              onChanged: (v) => _mealFrequencyBand = v,
            ),
            _yesNoSwitch('Snacks given?', _snacksGiven, (v) => _snacksGiven = v),
          ] else if (_isAge9to12Months) ...[
            _dropdownField(
              label: 'Meals per day (yesterday) *',
              value: _mealFrequencyBand,
              options: const ['0-2', '3', '4 or more'],
              onChanged: (v) => _mealFrequencyBand = v,
            ),
            _yesNoSwitch('Snacks given?', _snacksGiven, (v) => _snacksGiven = v),
          ] else ...[
            _dropdownField(
              label: 'Meals per day (yesterday) *',
              value: _mealFrequencyBand,
              options: const ['0-2', '3', '4 or more'],
              onChanged: (v) => _mealFrequencyBand = v,
            ),
            _dropdownField(
              label: 'Snacks per day?',
              value: _snacksPerDayBand,
              options: const ['None', '1', '2 or more'],
              onChanged: (v) => _snacksPerDayBand = v,
            ),
          ],
          const SizedBox(height: 8),
          const Text('Food groups consumed yesterday (24-hour recall) *', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _iycfFoodGroups.keys.map((group) {
              final selected = _iycfFoodGroups[group] ?? false;
              return FilterChip(
                label: Text(group),
                selected: selected,
                onSelected: (value) => setState(() => _iycfFoodGroups[group] = value),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          _numberField('Milk feeds per day (24-hour recall)', _milkFeedsPerDayController),
          if (_isAge6to9Months)
            _dropdownField(
              label: 'Feeding assistance',
              value: _feedingAssistance,
              options: const ['Self-fed', 'Fed by caregiver', 'Forced feeding'],
              onChanged: (v) => _feedingAssistance = v,
            ),
          if (_isAge9to12Months) ...[
            _yesNoSwitch('Animal-source foods consumed?', _animalSourceFoodsConsumed, (v) => _animalSourceFoodsConsumed = v),
            _dropdownField(
              label: 'Food consistency',
              value: _foodConsistency,
              options: const ['Thin liquid', 'Semi-solid', 'Thick mashed', 'Family food'],
              onChanged: (v) => _foodConsistency = v,
            ),
            _yesNoSwitch('Child self-feeding attempts?', _selfFeedingAttempts, (v) => _selfFeedingAttempts = v),
          ],
          if (_isAge12to24Months) ...[
            _yesNoSwitch('Animal-source foods consumed?', _animalSourceFoodsConsumed, (v) => _animalSourceFoodsConsumed = v),
            _dropdownField(
              label: 'Milk intake per day',
              value: _milkIntakeType,
              options: const ['Breastmilk only', 'Animal milk', 'Both', 'None'],
              onChanged: (v) => _milkIntakeType = v,
            ),
            _dropdownField(
              label: 'Feeding behavior',
              value: _feedingBehavior,
              options: const ['Eats independently', 'Needs assistance', 'Refuses food often', 'Forced feeding'],
              onChanged: (v) => _feedingBehavior = v,
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isAge24to36Months
              ? '24-36 months: family diet, diversity and junk exposure become key.'
              : (_isAge36to48Months
                  ? '36-48 months: preschool pattern with sugary drink risk.'
                  : (_isAge48to60Months
                      ? '48-60 months: add screen time and overweight-risk markers.'
                      : '60-72 months: school-readiness stage with activity and screen-time tracking.')),
          style: const TextStyle(color: Color(0xFF546E7A), fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 10),
        _dropdownField(
          label: 'Meals per day (yesterday) *',
          value: _mealFrequencyBand,
          options: const ['<3', '3', '4 or more'],
          onChanged: (v) => _mealFrequencyBand = v,
        ),
        _dropdownField(
          label: 'Snacks per day?',
          value: _snacksPerDayBand,
          options: const ['None', '1', '2 or more'],
          onChanged: (v) => _snacksPerDayBand = v,
        ),
        const Text('Food groups consumed yesterday (24-hour recall) *', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _iycfFoodGroups.keys.map((group) {
            final selected = _iycfFoodGroups[group] ?? false;
            return FilterChip(
              label: Text(group),
              selected: selected,
              onSelected: (value) => setState(() => _iycfFoodGroups[group] = value),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        _yesNoSwitch('Animal-source foods consumed?', _animalSourceFoodsConsumed, (v) => _animalSourceFoodsConsumed = v),
        if (_isAge24to36Months)
          _dropdownField(
            label: 'Milk intake per day',
            value: _milkIntakeType,
            options: const ['<200 ml', '200-400 ml', '>400 ml'],
            onChanged: (v) => _milkIntakeType = v,
          ),
        _dropdownField(
          label: 'Junk/ultra-processed food (last week)',
          value: _junkFoodBand,
          options: const ['None', '1-2 times', '3 or more times'],
          onChanged: (v) => _junkFoodBand = v,
        ),
        _dropdownField(
          label: 'Sugary drinks consumption',
          value: _sweetDrinksBand,
          options: const ['None', 'Occasionally', 'Daily'],
          onChanged: (v) => _sweetDrinksBand = v,
        ),
        if (_isAge48to60Months || _isAge60to72Months)
          _dropdownField(
            label: 'Screen time per day',
            value: _screenTimeBand,
            options: const ['<1 hour', '1-2 hours', '>2 hours'],
            onChanged: (v) => _screenTimeBand = v,
          ),
        if (_isAge60to72Months)
          _dropdownField(
            label: 'Physical activity per day',
            value: _physicalActivityBand,
            options: const ['<30 minutes', '30-60 minutes', '>60 minutes'],
            onChanged: (v) => _physicalActivityBand = v,
          ),
      ],
    );
  }

  String _feedingSectionTitle() {
    if (_isAge0to3Months) return 'SECTION 3: Feeding Practices (Age 0-3 months)';
    if (_isAge3to6Months) return 'SECTION 3: Feeding Practices (Age 3-6 months)';
    if (_isAge6to9Months) return 'SECTION 3: Feeding Practices (Age 6-9 months)';
    if (_isAge9to12Months) return 'SECTION 3: Feeding Practices (Age 9-12 months)';
    if (_isAge12to24Months) return 'SECTION 3: Feeding Practices (Age 12-24 months)';
    if (_isAge24to36Months) return 'SECTION 3: Feeding Practices (Age 24-36 months)';
    if (_isAge36to60Months) return 'SECTION 3: Feeding Practices (Age 36-60 months)';
    return 'SECTION 3: Feeding Practices (Age 60-72 months)';
  }

  Widget _buildMicronutrientsSection() {
    if (_isAge0to3Months) {
      return Column(
        children: [
          _yesNoSwitch('Vitamin K given at birth? (if available)', _vitaminKGivenAtBirth, (v) => _vitaminKGivenAtBirth = v),
          _yesNoSwitch('Immunization up to date?', _immunizationUpToDate, (v) => _immunizationUpToDate = v),
          _readOnlyField('Low birth weight (<2.5 kg)? (Auto)', _lowBirthWeightFlag ? 'Yes' : 'No'),
        ],
      );
    }

    if (_isAge3to6Months) {
      return Column(
        children: [
          _yesNoSwitch('Immunization up to date?', _immunizationUpToDate, (v) => _immunizationUpToDate = v),
          _yesNoSwitch('Vitamin D supplementation? (if applicable)', _vitaminDSupplementation, (v) => _vitaminDSupplementation = v),
          _readOnlyField('Low birth weight (<2.5 kg)? (Auto)', _lowBirthWeightFlag ? 'Yes' : 'No'),
        ],
      );
    }

    if (_isAge6to9Months) {
      return Column(
        children: [
          _yesNoSwitch('Vitamin A dose received? (usually after 9 months)', _vitaminADose, (v) => _vitaminADose = v),
          _yesNoSwitch('Iron supplementation?', _ironSupplementation, (v) => _ironSupplementation = v),
          _yesNoSwitch('Immunization up to date?', _immunizationUpToDate, (v) => _immunizationUpToDate = v),
          _yesNoSwitch('Deworming done? (usually after 12 months)', _dewormingLastSixMonths, (v) => _dewormingLastSixMonths = v),
        ],
      );
    }

    if (_isAge9to12Months) {
      return Column(
        children: [
          _yesNoSwitch('Vitamin A dose received? *', _vitaminADose, (v) => _vitaminADose = v),
          _yesNoSwitch('Iron supplementation?', _ironSupplementation, (v) => _ironSupplementation = v),
          _yesNoSwitch('Immunization up to date?', _immunizationUpToDate, (v) => _immunizationUpToDate = v),
          _yesNoSwitch('Deworming done? (usually after 12 months)', _dewormingLastSixMonths, (v) => _dewormingLastSixMonths = v),
        ],
      );
    }

    return Column(
      children: [
        _yesNoSwitch('Deworming done in last 6 months? *', _dewormingLastSixMonths, (v) => _dewormingLastSixMonths = v),
        _yesNoSwitch('Iron supplementation?', _ironSupplementation, (v) => _ironSupplementation = v),
        _yesNoSwitch('Vitamin A dose received?', _vitaminADose, (v) => _vitaminADose = v),
        _yesNoSwitch('Immunization up to date?', _immunizationUpToDate, (v) => _immunizationUpToDate = v),
      ],
    );
  }

  Widget _buildRiskAndLifestyleSection() {
    if (_isAge0to3Months) {
      return Column(
        children: [
          _yesNoSwitch('Poor weight gain?', _poorWeightGain, (v) => _poorWeightGain = v),
          _yesNoSwitch('Lethargy?', _lethargic, (v) => _lethargic = v),
          _yesNoSwitch('Fever?', _fever, (v) => _fever = v),
          _yesNoSwitch('Diarrhea?', _frequentDiarrhea, (v) => _frequentDiarrhea = v),
          _yesNoSwitch('Vomiting?', _vomiting, (v) => _vomiting = v),
          _yesNoSwitch('Convulsions?', _convulsions, (v) => _convulsions = v),
        ],
      );
    }

    if (_isAge3to6Months) {
      return Column(
        children: [
          _yesNoSwitch('Poor weight gain?', _poorWeightGain, (v) => _poorWeightGain = v),
          _yesNoSwitch('Fever?', _fever, (v) => _fever = v),
          _yesNoSwitch('Diarrhea?', _frequentDiarrhea, (v) => _frequentDiarrhea = v),
          _yesNoSwitch('Repeated infections?', _repeatedIllness, (v) => _repeatedIllness = v),
          _yesNoSwitch('Lethargy?', _lethargic, (v) => _lethargic = v),
          _yesNoSwitch('Persistent vomiting?', _persistentVomiting, (v) => _persistentVomiting = v),
        ],
      );
    }

    if (_isAge6to9Months) {
      return Column(
        children: [
          _yesNoSwitch('Diarrhea in last 2 weeks?', _frequentDiarrhea, (v) => _frequentDiarrhea = v),
          _yesNoSwitch('Repeated illness?', _repeatedIllness, (v) => _repeatedIllness = v),
          _yesNoSwitch('Poor appetite?', _poorAppetite, (v) => _poorAppetite = v),
          _yesNoSwitch('Vomiting?', _vomiting, (v) => _vomiting = v),
          _yesNoSwitch('Swelling in feet?', _swellingFeet, (v) => _swellingFeet = v),
        ],
      );
    }

    if (_isAge9to12Months) {
      return Column(
        children: [
          _yesNoSwitch('Diarrhea in last 2 weeks?', _frequentDiarrhea, (v) => _frequentDiarrhea = v),
          _yesNoSwitch('Repeated infections?', _repeatedIllness, (v) => _repeatedIllness = v),
          _yesNoSwitch('Poor appetite?', _poorAppetite, (v) => _poorAppetite = v),
          _yesNoSwitch('Swelling in feet?', _swellingFeet, (v) => _swellingFeet = v),
          _yesNoSwitch('Feeding difficulty?', _feedingDifficultySymptom, (v) => _feedingDifficultySymptom = v),
        ],
      );
    }

    if (_isAge12to24Months) {
      return Column(
        children: [
          _yesNoSwitch('Diarrhea in last 2 weeks?', _frequentDiarrhea, (v) => _frequentDiarrhea = v),
          _yesNoSwitch('Frequent illness?', _repeatedIllness, (v) => _repeatedIllness = v),
          _yesNoSwitch('Poor appetite?', _poorAppetite, (v) => _poorAppetite = v),
          _yesNoSwitch('Swelling in feet?', _swellingFeet, (v) => _swellingFeet = v),
          _yesNoSwitch('Weight loss recently?', _weightLossRecently, (v) => _weightLossRecently = v),
        ],
      );
    }

    if (_isAge24to36Months) {
      return Column(
        children: [
          _yesNoSwitch('Diarrhea in last 2 weeks?', _frequentDiarrhea, (v) => _frequentDiarrhea = v),
          _yesNoSwitch('Repeated respiratory infections?', _recurrentRespiratoryInfections, (v) => _recurrentRespiratoryInfections = v),
          _yesNoSwitch('Poor appetite?', _poorAppetite, (v) => _poorAppetite = v),
          _yesNoSwitch('Weight loss recently?', _weightLossRecently, (v) => _weightLossRecently = v),
          _yesNoSwitch('Swelling in feet?', _swellingFeet, (v) => _swellingFeet = v),
        ],
      );
    }

    if (_isAge36to48Months) {
      return Column(
        children: [
          _yesNoSwitch('Diarrhea in last 2 weeks?', _frequentDiarrhea, (v) => _frequentDiarrhea = v),
          _yesNoSwitch('Recurrent respiratory infections?', _recurrentRespiratoryInfections, (v) => _recurrentRespiratoryInfections = v),
          _yesNoSwitch('Weight loss recently?', _weightLossRecently, (v) => _weightLossRecently = v),
          _yesNoSwitch('Swelling in feet?', _swellingFeet, (v) => _swellingFeet = v),
          _yesNoSwitch('Low energy / lethargy?', _lowEnergy, (v) => _lowEnergy = v),
        ],
      );
    }

    if (_isAge48to60Months) {
      return Column(
        children: [
          _yesNoSwitch('Diarrhea in last 2 weeks?', _frequentDiarrhea, (v) => _frequentDiarrhea = v),
          _yesNoSwitch('Recurrent infections?', _repeatedIllness, (v) => _repeatedIllness = v),
          _yesNoSwitch('Weight loss recently?', _weightLossRecently, (v) => _weightLossRecently = v),
          _yesNoSwitch('Low activity level?', _lowActivityLevel, (v) => _lowActivityLevel = v),
          _yesNoSwitch('Swelling in feet?', _swellingFeet, (v) => _swellingFeet = v),
        ],
      );
    }

    return Column(
      children: [
        _yesNoSwitch('Diarrhea in last 2 weeks?', _frequentDiarrhea, (v) => _frequentDiarrhea = v),
        _yesNoSwitch('Recurrent respiratory infections?', _recurrentRespiratoryInfections, (v) => _recurrentRespiratoryInfections = v),
        _yesNoSwitch('Weight loss recently?', _weightLossRecently, (v) => _weightLossRecently = v),
        _yesNoSwitch('Low energy?', _lowEnergy, (v) => _lowEnergy = v),
        _yesNoSwitch('Swelling in feet?', _swellingFeet, (v) => _swellingFeet = v),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nutrition Screening'),
        backgroundColor: const Color(0xFF0D5BA7),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionCard(
            title: 'Nutrition Inputs',
            child: Column(
              children: [
                _numberField('Birth Weight (kg) *', _birthWeightController),
                const SizedBox(height: 8),
                _numberField('Weight (kg) *', _weightController),
                const SizedBox(height: 8),
                _numberField('Height / Length (cm) *', _heightController),
                const SizedBox(height: 8),
                _numberField('MUAC (cm) *', _muacController),
                const SizedBox(height: 8),
                _numberField('Hemoglobin (g/dL) *', _hemoglobinController),
                const SizedBox(height: 8),
                _yesNoSwitch(
                  'Recent Illness (Last 2 weeks?)',
                  _recentIllness,
                  (v) => _recentIllness = v,
                ),
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'WHO LMS logic: score = (Underweightx2) + (Stuntingx3) + (Wastingx2) + (Anemiax1).',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Risk bands: 0=Low, 1-3=Medium, 4-8=High.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _continue,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2F95EA),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(_isSubmitting ? 'Saving...' : 'Submit Assessment'),
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}
