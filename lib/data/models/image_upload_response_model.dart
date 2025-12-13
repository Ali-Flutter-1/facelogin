class ImageUploadResponseModel {
  final String? id;
  final String? fileId;
  final String? imageId;
  final String? path;
  final String? url;
  final String? frontImageId;
  final String? backImageId;
  final Map<String, dynamic>? data;

  ImageUploadResponseModel({
    this.id,
    this.fileId,
    this.imageId,
    this.path,
    this.url,
    this.frontImageId,
    this.backImageId,
    this.data,
  });

  factory ImageUploadResponseModel.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return ImageUploadResponseModel(
      id: json['id']?.toString() ?? data?['id']?.toString(),
      fileId: json['file_id']?.toString() ?? data?['file_id']?.toString(),
      imageId: json['image_id']?.toString() ?? data?['image_id']?.toString(),
      path: json['path']?.toString() ?? data?['path']?.toString(),
      url: json['url']?.toString() ?? data?['url']?.toString(),
      frontImageId: data?['front_image_id']?.toString(),
      backImageId: data?['back_image_id']?.toString(),
      data: data,
    );
  }

  String? getImageId(String fieldName) {
    if (fieldName == 'id_front_image') return frontImageId;
    if (fieldName == 'id_back_image') return backImageId;
    return id ?? fileId ?? imageId ?? path ?? url;
  }
}

