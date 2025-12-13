class LoginResponseModel {
  final String? accessToken;
  final String? refreshToken;
  final Map<String, dynamic>? data;

  LoginResponseModel({
    this.accessToken,
    this.refreshToken,
    this.data,
  });

  factory LoginResponseModel.fromJson(Map<String, dynamic> json) {
    final responseData = json['data'];
    return LoginResponseModel(
      accessToken: responseData?['access_token'],
      refreshToken: responseData?['refresh_token'],
      data: responseData,
    );
  }

  bool get hasValidTokens =>
      accessToken != null && accessToken!.isNotEmpty &&
      refreshToken != null && refreshToken!.isNotEmpty;
}

