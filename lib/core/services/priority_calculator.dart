class PriorityCalculator {
  /// Default category severity scores (0-100)
  static const Map<String, double> categorySeverityDefaults = {
    'Pothole': 70.0,
    'Garbage': 50.0,
    'Water Supply': 80.0,
    'Drainage': 70.0,
    'Streetlight': 40.0,
    'Road Damage': 80.0,
    'Public Area': 40.0,
    'Other': 30.0,
  };

  /// Returns default severity score (0-100) for a category
  static double getCategorySeverity(String category) {
    return categorySeverityDefaults[category] ?? 30.0;
  }

  /// Maps numerical severity score to level
  static String mapScoreToSeverityLevel(double score) {
    if (score >= 80) return 'CRITICAL';
    if (score >= 60) return 'HIGH';
    if (score >= 40) return 'MEDIUM';
    return 'LOW';
  }

  /// Maps severity level string ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL') to numerical score
  static double mapSeverityLevelToScore(String level) {
    switch (level.toUpperCase()) {
      case 'CRITICAL':
        return 90.0;
      case 'HIGH':
        return 70.0;
      case 'MEDIUM':
        return 50.0;
      case 'LOW':
      default:
        return 30.0;
    }
  }

  /// Community Support Score (0-100):
  /// Ratio: upvotes / (upvotes + downvotes)
  /// Safely handles 0 votes (returns 0.0)
  static double calculateCommunitySupportScore({
    required int upvotes,
    required int downvotes,
  }) {
    final total = upvotes + downvotes;
    if (total == 0) return 0.0;
    final ratio = upvotes / total;
    return (ratio * 100.0).clamp(0.0, 100.0);
  }

  /// Related Complaint Score (0-100):
  /// 1 complaint = 20
  /// 2 complaints = 40
  /// 3 complaints = 60
  /// 4 complaints = 80
  /// 5+ complaints = 100
  static double calculateRelatedComplaintScore(int relatedCount) {
    if (relatedCount <= 0) return 0.0;
    if (relatedCount == 1) return 20.0;
    if (relatedCount == 2) return 40.0;
    if (relatedCount == 3) return 60.0;
    if (relatedCount == 4) return 80.0;
    return 100.0;
  }

  /// Confirmation Score (0-100):
  /// Configurable maximum (default 10 = 100.0)
  static double calculateConfirmationScore(
    int confirmationCount, {
    int maxConfirmations = 10,
  }) {
    if (confirmationCount <= 0) return 0.0;
    final score = (confirmationCount / maxConfirmations) * 100.0;
    return score.clamp(0.0, 100.0);
  }

  /// Hotspot Score (0-100):
  /// 1 = 0
  /// 2 = 40
  /// 3 = 60
  /// 4 = 80
  /// 5+ = 100
  static double calculateHotspotScore(int groupComplaintCount) {
    if (groupComplaintCount <= 1) return 0.0;
    if (groupComplaintCount == 2) return 40.0;
    if (groupComplaintCount == 3) return 60.0;
    if (groupComplaintCount == 4) return 80.0;
    return 100.0;
  }

  /// Hotspot label based on group count:
  /// 2-3 complaints: Complaint Zone
  /// 4-5 complaints: High Activity Zone
  /// 6+ complaints: Hotspot
  static String calculateHotspotLevel(int groupCount) {
    if (groupCount >= 6) return 'Hotspot';
    if (groupCount >= 4) return 'High Activity Zone';
    if (groupCount >= 2) return 'Complaint Zone';
    return 'Normal';
  }

  /// Deterministic mathematical Priority Score formula (0-100):
  /// Priority Score =
  /// (Severity Score × 0.30)
  /// + (Community Support Score × 0.20)
  /// + (Related Complaint Score × 0.25)
  /// + (Confirmation Score × 0.15)
  /// + (Hotspot Score × 0.10)
  static double calculatePriorityScore({
    required double severityScore,
    required double communitySupportScore,
    required double relatedComplaintScore,
    required double confirmationScore,
    required double hotspotScore,
  }) {
    final score = (severityScore * 0.30) +
        (communitySupportScore * 0.20) +
        (relatedComplaintScore * 0.25) +
        (confirmationScore * 0.15) +
        (hotspotScore * 0.10);

    return score.clamp(0.0, 100.0);
  }

  /// Priority Level:
  /// 0–39: LOW
  /// 40–59: MEDIUM
  /// 60–79: HIGH
  /// 80–100: CRITICAL
  static String getPriorityLevel(double score) {
    if (score >= 80.0) return 'CRITICAL';
    if (score >= 60.0) return 'HIGH';
    if (score >= 40.0) return 'MEDIUM';
    return 'LOW';
  }
}

