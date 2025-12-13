class ApiErrorModel {
  final String? code;
  final String? message;
  final Map<String, dynamic>? error;

  ApiErrorModel({
    this.code,
    this.message,
    this.error,
  });

  factory ApiErrorModel.fromJson(Map<String, dynamic> json) {
    final errorData = json['error'];
    
    // Handle case where error is a Map
    if (errorData != null && errorData is Map) {
      try {
        // Try to cast to Map<String, dynamic>
        final errorMap = errorData is Map<String, dynamic>
            ? errorData
            : Map<String, dynamic>.from(errorData);
        
        return ApiErrorModel(
          code: errorMap['code']?.toString(),
          message: errorMap['message']?.toString(),
          error: errorMap,
        );
      } catch (e) {
        // If conversion fails, treat as string message
        return ApiErrorModel(
          message: errorData.toString(),
          error: null,
        );
      }
    }
    
    // Handle case where error is a string or other type
    return ApiErrorModel(
      message: errorData?.toString(),
      error: null,
    );
  }

  String get displayMessage {
    if (code != null && code!.isNotEmpty) return code!;
    if (message != null && message!.isNotEmpty) return message!;
    if (error != null) {
      // Try to extract message from error map
      final errorMsg = error!['message']?.toString();
      if (errorMsg != null && errorMsg.isNotEmpty) return errorMsg;
      return error.toString();
    }
    return 'An error occurred';
  }
}

