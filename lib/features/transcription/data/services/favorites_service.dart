import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../../core/config/app_config.dart';
import '../../../../core/logging/app_logger.dart';

class FavoriteMedicineDto {
  final String id;
  final String genericName;
  final String? brandName;
  final String? category;
  final String? dose;
  final String? frequency;
  final String? duration;

  FavoriteMedicineDto({
    required this.id,
    required this.genericName,
    this.brandName,
    this.category,
    this.dose,
    this.frequency,
    this.duration,
  });

  factory FavoriteMedicineDto.fromJson(Map<String, dynamic> json) {
    return FavoriteMedicineDto(
      id: json['id']?.toString() ?? '',
      genericName: json['genericName']?.toString() ?? json['GenericName']?.toString() ?? '',
      brandName: json['brandName']?.toString() ?? json['BrandName']?.toString(),
      category: json['category']?.toString() ?? json['Category']?.toString(),
      dose: json['dose']?.toString() ?? json['Dose']?.toString(),
      frequency: json['frequency']?.toString() ?? json['Frequency']?.toString(),
      duration: json['duration']?.toString() ?? json['Duration']?.toString(),
    );
  }
}

final favoritesServiceProvider = Provider<FavoritesService>((ref) {
  final config = ref.watch(appConfigProvider);
  return FavoritesService(clientApiBaseUrl: config.clientApiBaseUrl);
});

final favoriteMedicinesProvider = FutureProvider<List<FavoriteMedicineDto>>((ref) async {
  final service = ref.watch(favoritesServiceProvider);
  return service.fetchFavorites();
});

class FavoritesService {
  final String clientApiBaseUrl;

  FavoritesService({required this.clientApiBaseUrl});

  static final List<FavoriteMedicineDto> defaultFallbackFavorites = [
    FavoriteMedicineDto(
      id: '1',
      genericName: 'Metformin',
      brandName: 'Glucophage',
      dose: '500 mg',
      frequency: 'BD',
      duration: '30 days',
    ),
    FavoriteMedicineDto(
      id: '2',
      genericName: 'Paracetamol',
      brandName: 'Panadol',
      dose: '500 mg',
      frequency: 'TDS',
      duration: '5 days',
    ),
    FavoriteMedicineDto(
      id: '3',
      genericName: 'Amoxicillin',
      brandName: 'Amoxil',
      dose: '500 mg',
      frequency: 'TDS',
      duration: '7 days',
    ),
    FavoriteMedicineDto(
      id: '4',
      genericName: 'Omeprazole',
      brandName: 'Losec',
      dose: '20 mg',
      frequency: 'Daily',
      duration: '14 days',
    ),
    FavoriteMedicineDto(
      id: '5',
      genericName: 'Cetirizine',
      brandName: 'Zyrtec',
      dose: '10 mg',
      frequency: 'Nightly',
      duration: '10 days',
    ),
    FavoriteMedicineDto(
      id: '6',
      genericName: 'Salbutamol',
      brandName: 'Ventolin',
      dose: '100 mcg',
      frequency: 'PRN',
      duration: 'As needed',
    ),
  ];

  Future<List<FavoriteMedicineDto>> fetchFavorites() async {
    try {
      final uri = Uri.parse('$clientApiBaseUrl/api/favorites');
      AppLogger.i('Fetching favourite medicines from $uri');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final list = data.map((e) => FavoriteMedicineDto.fromJson(e as Map<String, dynamic>)).toList();
        if (list.isNotEmpty) {
          return list;
        }
      }
    } catch (e) {
      AppLogger.w('Failed to fetch favorites from API, using fallback: $e');
    }
    return defaultFallbackFavorites;
  }
}
