class ActionResult {
  final bool success;
  final String message;

  const ActionResult({required this.success, required this.message});

  factory ActionResult.ok(String message) =>
      ActionResult(success: true, message: message);

  factory ActionResult.fail(String message) =>
      ActionResult(success: false, message: message);
}
