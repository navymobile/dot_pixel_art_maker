import 'package:dot_pixel_art_maker/domain/dot_model.dart';

class GenLogic {
  // Logic to increment generation is encapsulated here,
  // though simplistic for now, it allows for future expansion (e.g., mutation rules).

  static DotModel incrementGen(DotModel source) {
    return DotModel.fromExchange(source);
  }
}
