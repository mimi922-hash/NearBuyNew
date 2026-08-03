import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────
// BRAND CONSTANTS
// ─────────────────────────────────────────────────────────────────────────
class _NB {
  static const Color navy      = Color(0xFF0E2A47);
  static const Color navyLight = Color(0xFF1A3A5C);
  static const Color orange    = Color(0xFFFF6A1A);
  static const Color bg        = Color(0xFFF0F3F8);
  static const Color surface   = Colors.white;
  static const Color border    = Color(0xFFE2E8F0);
  static const Color textGrey  = Color(0xFF94A3B8);
  static const Color green     = Color(0xFF2E9E6B);
  static const Color greenBg   = Color(0xFFE8F5EE);
  static const Color red       = Color(0xFFE53935);
  static const Color redBg     = Color(0xFFFFECEC);
  static const Color orangeBg  = Color(0xFFFFF0E8);
  static const Color yellow    = Color(0xFFF5A623);
  static const Color yellowBg  = Color(0xFFFFFBE8);
}

// ─────────────────────────────────────────────────────────────────────────
// WIDGET
// ─────────────────────────────────────────────────────────────────────────
class AddProductPage extends StatefulWidget {
  final String shopId;
  final String? editProductId;
  final Map<String, dynamic>? editData;

  const AddProductPage({
    super.key,
    required this.shopId,
    this.editProductId,
    this.editData,
  });

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage>
    with SingleTickerProviderStateMixin {
  // ── State ──────────────────────────────────────────
  final _formKey         = GlobalKey<FormState>();
  final _nameController  = TextEditingController();
  final _descController  = TextEditingController();
  final _priceController = TextEditingController();
  final _quantityController = TextEditingController();
  bool    _loading       = false;
  File?   _productImage;
  String? _imageUrl;
  bool    _imageMissing  = false;
  final   picker         = ImagePicker();
  
  // ── New controllers for tracking ──
  final _nameFocusNode = FocusNode();
  final _descFocusNode = FocusNode();
  final _priceFocusNode = FocusNode();
  final _quantityFocusNode = FocusNode();

  // ── Cloudinary credentials ────────────────────────
  static const String _cloudName    = 'dxzaqavfj';
  static const String _uploadPreset = 'nearbuy_preset';

  // ── Animation ────────────────────────────────────
  late AnimationController _animController;
  late Animation<double>   _fadeAnim;
  late Animation<Offset>   _slideAnim;

  // ── Lifecycle ────────────────────────────────────
  @override
  void initState() {
    super.initState();
    if (widget.editData != null) {
      _nameController.text  = widget.editData!['name']        ?? '';
      _descController.text  = widget.editData!['description'] ?? '';
      _priceController.text = (widget.editData!['price'] ?? '').toString();
      _quantityController.text = (widget.editData!['quantity'] ?? 0).toString();
      _imageUrl             = widget.editData!['image_url'];
    }
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim  = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06), end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
    
    // Add listeners for character counting
    _nameController.addListener(() => setState(() {}));
    _descController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _animController.dispose();
    _nameController.dispose();
    _descController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    _nameFocusNode.dispose();
    _descFocusNode.dispose();
    _priceFocusNode.dispose();
    _quantityFocusNode.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════
  // LOGIC
  // ══════════════════════════════════════════════════

  // ── Image Picker with Camera & Gallery ──
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      
      if (picked != null) {
        // Validate image size (max 10MB)
        final File imageFile = File(picked.path);
        final int fileSize = await imageFile.length();
        if (fileSize > 10 * 1024 * 1024) {
          _showSnack('Image size should be less than 10MB', _NB.red);
          return;
        }
        
        setState(() {
          _productImage = imageFile;
          _imageMissing = false;
        });
      }
    } catch (e) {
      _showSnack('Error picking image: $e', _NB.red);
    }
  }

  // ── Show Image Picker Modal ──
  void _showImagePickerModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _imagePickerOption(
                    icon: Icons.photo_camera,
                    label: 'Camera',
                    color: _NB.navy,
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.camera);
                    },
                  ),
                  _imagePickerOption(
                    icon: Icons.photo_library,
                    label: 'Gallery',
                    color: _NB.orange,
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.gallery);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _imagePickerOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                )),
          ],
        ),
      ),
    );
  }

  Future<String?> uploadToCloudinary(File image) async {
    try {
      final url = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');
      final request = http.MultipartRequest('POST', url);
      request.fields['upload_preset'] = _uploadPreset;
      request.files.add(
        await http.MultipartFile.fromPath('file', image.path),
      );
      final response = await request.send();
      final res = await http.Response.fromStream(response);
      if (response.statusCode == 200) {
        final data = json.decode(res.body);
        return data['secure_url'];
      }
      return null;
    } catch (e) {
      _showSnack('Upload failed: $e', _NB.red);
      return null;
    }
  }

  // ── Validation ──
  bool _validate() {
    // 1. Image validation
    final bool hasImage = _productImage != null ||
        (_imageUrl != null && _imageUrl!.isNotEmpty);
    if (!hasImage) {
      setState(() => _imageMissing = true);
      _showSnack('Product image is required', _NB.red);
      return false;
    }

    // 2. Product name validation
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnack('Product name is required', _NB.red);
      return false;
    }
    if (name.length < 2) {
      _showSnack('Product name must be at least 2 characters', _NB.red);
      return false;
    }
    if (name.length > 50) {
      _showSnack('Product name cannot exceed 50 characters', _NB.red);
      return false;
    }
    // Validate only reasonable characters
    final RegExp validNameRegex = RegExp(r'^[a-zA-Z0-9\s\-\.\(\)&]+$');
    if (!validNameRegex.hasMatch(name)) {
      _showSnack('Product name contains invalid characters', _NB.red);
      return false;
    }

    // 3. Description validation (optional but length check if entered)
    final String desc = _descController.text.trim();
    if (desc.isNotEmpty && desc.length > 200) {
      _showSnack('Description cannot exceed 200 characters', _NB.red);
      return false;
    }

    // 4. Category validation - you already have category selection
    // (Assuming you have category dropdown - will add in UI)

    // 5. Quantity validation
    final String qtyText = _quantityController.text.trim();
    if (qtyText.isEmpty) {
      _showSnack('Quantity is required', _NB.red);
      return false;
    }
    final int? quantity = int.tryParse(qtyText);
    if (quantity == null) {
      _showSnack('Please enter a valid whole number for quantity', _NB.red);
      return false;
    }
    if (quantity < 0) {
      _showSnack('Quantity cannot be negative', _NB.red);
      return false;
    }
    if (quantity > 9999) {
      _showSnack('Maximum quantity is 9999', _NB.red);
      return false;
    }

    // 6. Price validation
    final String priceText = _priceController.text.trim();
    if (priceText.isEmpty) {
      _showSnack('Price is required', _NB.red);
      return false;
    }
    final double? price = double.tryParse(priceText);
    if (price == null || price < 0) {
      _showSnack('Please enter a valid price', _NB.red);
      return false;
    }
    if (price > 9999999.99) {
      _showSnack('Maximum price is 99,99,999.99', _NB.red);
      return false;
    }

    return true;
  }

  // ── Save Product ──
  void _saveProduct() async {
    if (!_validate()) return;

    setState(() => _loading = true);

    try {
      // Upload image if new image selected
      if (_productImage != null) {
        final uploadedUrl = await uploadToCloudinary(_productImage!);
        if (uploadedUrl != null) {
          _imageUrl = uploadedUrl;
        } else {
          setState(() => _loading = false);
          _showSnack('Failed to upload image', _NB.red);
          return;
        }
      }

      // ── Get quantity and auto-calculate stock status ──
      final int quantity = int.tryParse(_quantityController.text.trim()) ?? 0;
      final bool isOutOfStock = quantity <= 0;

      // ── Prepare data with existing field names ──
      final Map<String, dynamic> data = {
        'name': _nameController.text.trim(),
        'description': _descController.text.trim(),
        'price': double.tryParse(_priceController.text.trim()) ?? 0.0,
        'quantity': quantity,
        'out_of_stock': isOutOfStock,  // Auto-calculated from quantity
        'image_url': _imageUrl,
        'updated_at': Timestamp.now(),
      };

      // Add created_at only for new products
      if (widget.editProductId == null) {
        data['created_at'] = Timestamp.now();
        data['shopId'] = widget.shopId;
      }

      final collection = FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .collection('products');

      if (widget.editProductId != null) {
        // Update existing product - only changed fields
        await collection.doc(widget.editProductId).update(data);
        if (mounted) {
          _showSnack('Product updated successfully!', _NB.green);
          Navigator.pop(context, true);
        }
      } else {
        // Add new product
        await collection.add(data);
        if (mounted) {
          _showSnack('Product added successfully!', _NB.orange);
          // Clear form for new product
          _nameController.clear();
          _descController.clear();
          _priceController.clear();
          _quantityController.clear();
          setState(() {
            _productImage = null;
            _imageUrl = null;
            _imageMissing = false;
          });
        }
      }
    } catch (e) {
      _showSnack('Error saving product: $e', _NB.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _deleteProduct(String productId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titlePadding: EdgeInsets.zero,
        title: Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: _NB.navy,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_outline,
                  color: Colors.red, size: 22),
            ),
            const SizedBox(width: 12),
            const Text('Delete Product',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                )),
          ]),
        ),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Are you sure you want to delete this product?\nThis action cannot be undone.',
            style: TextStyle(color: Color(0xFF475569), height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 10,
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold,
                )),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('shops')
            .doc(widget.shopId)
            .collection('products')
            .doc(productId)
            .delete();
        if (mounted) {
          _showSnack('Product deleted successfully', _NB.green);
        }
      } catch (e) {
        _showSnack('Error deleting product: $e', _NB.red);
      }
    }
  }

  // ══════════════════════════════════════════════════
  // UI HELPERS
  // ══════════════════════════════════════════════════

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.info_outline, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.all(16),
    ));
  }

  InputDecoration _inputDec({
    required String label,
    IconData? icon,
    Widget? prefixWidget,
    String? hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixWidget ??
          Icon(icon, color: _NB.orange, size: 20),
      suffix: suffix,
      floatingLabelStyle: const TextStyle(
        color: _NB.navy, fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: _NB.bg,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16, vertical: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _NB.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _NB.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _NB.orange, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade400),
      ),
    );
  }

  Widget _sectionHeader(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Container(
          width: 4, height: 20,
          decoration: BoxDecoration(
            color: _NB.orange,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, color: _NB.navy, size: 18),
        const SizedBox(width: 6),
        Text(text,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: _NB.navy,
          ),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════
  // IMAGE PICKER WIDGET
  // ══════════════════════════════════════════════════

  Widget _imagePicker() {
    final hasImage = _productImage != null || 
                    (_imageUrl != null && _imageUrl!.isNotEmpty);

    final Color borderColor = _imageMissing
        ? _NB.red
        : hasImage
            ? _NB.orange
            : _NB.border;
    final double borderWidth = (_imageMissing || hasImage) ? 2.0 : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Image Preview ──
        GestureDetector(
          onTap: _showImagePickerModal,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              color: hasImage ? Colors.transparent : _NB.bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: borderWidth),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: _productImage != null
                  ? Stack(fit: StackFit.expand, children: [
                      Image.file(_productImage!, fit: BoxFit.cover),
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          color: Colors.black.withOpacity(0.45),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.edit, color: Colors.white, size: 16),
                              SizedBox(width: 6),
                              Text('Tap to change image',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                    ])
                  : _imageUrl != null && _imageUrl!.isNotEmpty
                      ? Stack(fit: StackFit.expand, children: [
                          Image.network(
                            _imageUrl!,
                            fit: BoxFit.cover,
                            loadingBuilder: (_, child, progress) =>
                                progress == null
                                    ? child
                                    : const Center(
                                        child: CircularProgressIndicator(
                                          color: _NB.orange,
                                        )),
                            errorBuilder: (_, __, ___) => _imagePlaceholder(),
                          ),
                          Positioned(
                            bottom: 0, left: 0, right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              color: Colors.black.withOpacity(0.45),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.edit, color: Colors.white, size: 16),
                                  SizedBox(width: 6),
                                  Text('Tap to change image',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                          ),
                        ])
                      : _imagePlaceholder(showError: _imageMissing),
            ),
          ),
        ),
        
        // ── Image Instructions ──
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, 
                   size: 14, color: _imageMissing ? _NB.red : _NB.textGrey),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Use a clear and real photo of the product. Avoid blurry, dark, or unrelated images. Make sure the complete product is visible.',
                  style: TextStyle(
                    fontSize: 11,
                    color: _imageMissing ? _NB.red : _NB.textGrey,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        if (_imageMissing)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Row(children: [
              const Icon(Icons.error_outline, size: 13, color: _NB.red),
              const SizedBox(width: 4),
              const Text('Product image is required',
                  style: TextStyle(
                      fontSize: 11,
                      color: _NB.red,
                      fontWeight: FontWeight.w500)),
            ]),
          ),
      ],
    );
  }

  Widget _imagePlaceholder({bool showError = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: showError
                ? _NB.red.withOpacity(0.08)
                : _NB.orange.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(
            showError ? Icons.error_outline : Icons.add_photo_alternate_outlined,
            color: showError ? _NB.red : _NB.orange,
            size: 34,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          showError ? 'Image is required — Tap to add' : 'Tap to add product image',
          style: TextStyle(
            color: showError ? _NB.red : _NB.textGrey,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('JPG, PNG supported',
                style: TextStyle(color: _NB.textGrey, fontSize: 11)),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _NB.orangeBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('Max 10MB',
                  style: TextStyle(
                    color: _NB.orange,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  )),
            ),
          ],
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════
  // PRODUCT LIST
  // ══════════════════════════════════════════════════

  Widget _productList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .collection('products')
          .orderBy('created_at', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: _NB.orange),
            ),
          );
        }
        
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(children: [
              Icon(Icons.inventory_2_outlined,
                  size: 52, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text('No products added yet.',
                  style: TextStyle(
                      color: Colors.grey.shade400, fontSize: 14)),
            ]),
          );
        }
        
        final products = snapshot.data!.docs;
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: products.length,
          itemBuilder: (context, index) {
            final data = products[index].data() as Map<String, dynamic>;
            final productId = products[index].id;
            
            // ── Determine stock status from quantity ──
            final int quantity = data['quantity'] ?? 0;
            final bool isOutOfStock = quantity <= 0;
            final bool isLowStock = quantity > 0 && quantity <= 5;

            return Opacity(
              opacity: isOutOfStock ? 0.7 : 1.0,
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: _NB.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isOutOfStock
                        ? _NB.red.withOpacity(0.25)
                        : isLowStock
                            ? _NB.yellow.withOpacity(0.4)
                            : _NB.border,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: data['image_url'] != null &&
                                data['image_url'].toString().isNotEmpty
                            ? Image.network(
                                data['image_url'],
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _listImgPlaceholder(),
                              )
                            : _listImgPlaceholder(),
                      ),
                      if (isOutOfStock)
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              color: Colors.black.withOpacity(0.4),
                              alignment: Alignment.center,
                              child: const Text('OUT\nOF\nSTOCK',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 7,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.3)),
                            ),
                          ),
                        ),
                      if (isLowStock && !isOutOfStock)
                        Positioned(
                          top: 2,
                          right: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: _NB.yellow,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('LOW',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 6,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                    ]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['name'] ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isOutOfStock
                                  ? Colors.grey.shade500
                                  : _NB.navy,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isOutOfStock
                                      ? Colors.grey.shade100
                                      : _NB.orangeBg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Rs. ${data['price']}',
                                  style: TextStyle(
                                    color: isOutOfStock
                                        ? Colors.grey.shade400
                                        : _NB.orange,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              if (quantity > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isLowStock
                                        ? _NB.yellowBg
                                        : _NB.greenBg,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Qty: $quantity',
                                    style: TextStyle(
                                      color: isLowStock
                                          ? _NB.yellow
                                          : _NB.green,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (data['description'] != null &&
                              data['description'].toString().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              data['description'],
                              style: const TextStyle(
                                  color: _NB.textGrey, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    Column(children: [
                      _iconBtn(
                        icon: Icons.edit_outlined,
                        color: _NB.navy,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddProductPage(
                              shopId: widget.shopId,
                              editProductId: productId,
                              editData: data,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _iconBtn(
                        icon: Icons.delete_outline,
                        color: _NB.red,
                        onTap: () => _deleteProduct(productId),
                      ),
                    ]),
                  ]),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _listImgPlaceholder() => Container(
    width: 64,
    height: 64,
    decoration: BoxDecoration(
      color: _NB.orangeBg,
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Icon(Icons.image_outlined, color: _NB.orange, size: 26),
  );

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  // ══════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.editProductId != null;

    return Scaffold(
      backgroundColor: _NB.bg,
      appBar: AppBar(
        backgroundColor: _NB.navy,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            isEdit ? Icons.edit_outlined : Icons.add_circle_outline,
            color: _NB.orange, size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            isEdit ? 'Edit Product' : 'Add Product',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ]),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: _NB.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader(
                          isEdit ? 'Edit Product Details' : 'Product Details',
                          Icons.inventory_2_outlined,
                        ),

                        // ── Image Picker ──
                        _imagePicker(),
                        const SizedBox(height: 18),

                        // ── Product Name ──
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: _nameController,
                              focusNode: _nameFocusNode,
                              textCapitalization: TextCapitalization.words,
                              maxLength: 50,
                              decoration: _inputDec(
                                label: 'Product Name *',
                                icon: Icons.label_outline,
                                hint: 'e.g. Fresh Apples (1kg)',
                              ),
                              onChanged: (value) {
                                // Trim extra spaces
                                if (value != value.trim()) {
                                  _nameController.value = TextEditingValue(
                                    text: value.trim(),
                                    selection: TextSelection.collapsed(
                                      offset: value.trim().length,
                                    ),
                                  );
                                }
                              },
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Product name is required';
                                }
                                if (v.trim().length < 2) {
                                  return 'Minimum 2 characters required';
                                }
                                if (v.trim().length > 50) {
                                  return 'Maximum 50 characters allowed';
                                }
                                return null;
                              },
                            ),
                            // Character counter
                            Padding(
                              padding: const EdgeInsets.only(top: 4, right: 4),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '${_nameController.text.trim().length}/50',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _nameController.text.trim().length > 50
                                        ? _NB.red
                                        : _NB.textGrey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // ── Description ──
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: _descController,
                              focusNode: _descFocusNode,
                              maxLines: 3,
                              maxLength: 200,
                              decoration: _inputDec(
                                label: 'Description (optional)',
                                icon: Icons.description_outlined,
                                hint: 'Brief description of the product...',
                              ),
                              validator: (v) {
                                if (v != null && v.trim().length > 200) {
                                  return 'Maximum 200 characters allowed';
                                }
                                return null;
                              },
                            ),
                            // Character counter
                            Padding(
                              padding: const EdgeInsets.only(top: 4, right: 4),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '${_descController.text.trim().length}/200',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _descController.text.trim().length > 200
                                        ? _NB.red
                                        : _NB.textGrey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // ── Price ──
                        TextFormField(
                          controller: _priceController,
                          focusNode: _priceFocusNode,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: _inputDec(
                            label: 'Price (Rs.) *',
                            prefixWidget: Container(
                              alignment: Alignment.center,
                              width: 40,
                              child: const Text(
                                'Rs.',
                                style: TextStyle(
                                  color: _NB.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            hint: 'e.g. 150',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Price is required';
                            }
                            final price = double.tryParse(v.trim());
                            if (price == null) {
                              return 'Enter a valid price';
                            }
                            if (price < 0) {
                              return 'Price cannot be negative';
                            }
                            if (price > 9999999.99) {
                              return 'Maximum price is 99,99,999.99';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // ── Quantity ──
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: _quantityController,
                              focusNode: _quantityFocusNode,
                              keyboardType: TextInputType.number,
                              decoration: _inputDec(
                                label: 'Quantity *',
                                icon: Icons.numbers_outlined,
                                hint: 'e.g. 10 (0 for out of stock)',
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Quantity is required';
                                }
                                final quantity = int.tryParse(v.trim());
                                if (quantity == null) {
                                  return 'Enter a valid whole number';
                                }
                                if (quantity < 0) {
                                  return 'Quantity cannot be negative';
                                }
                                if (quantity > 9999) {
                                  return 'Maximum quantity is 9999';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 6),

                            // ── Live stock status indicator ──
                            Builder(
                              builder: (context) {
                                final qtyText = _quantityController.text.trim();
                                final qty = int.tryParse(qtyText);
                                String statusText;
                                Color statusColor;
                                Color statusBg;
                                IconData statusIcon;
                                
                                if (qty == null || qtyText.isEmpty) {
                                  statusText = 'Enter quantity to see stock status';
                                  statusColor = _NB.textGrey;
                                  statusBg = _NB.bg;
                                  statusIcon = Icons.info_outline;
                                } else if (qty <= 0) {
                                  statusText = 'Out of Stock (quantity is 0)';
                                  statusColor = _NB.red;
                                  statusBg = _NB.redBg;
                                  statusIcon = Icons.warning_rounded;
                                } else if (qty <= 5) {
                                  statusText = 'Low Stock (only $qty items left)';
                                  statusColor = _NB.yellow;
                                  statusBg = _NB.yellowBg;
                                  statusIcon = Icons.warning_rounded;
                                } else {
                                  statusText = 'In Stock ($qty items available)';
                                  statusColor = _NB.green;
                                  statusBg = _NB.greenBg;
                                  statusIcon = Icons.check_circle_rounded;
                                }

                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: statusBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: statusColor.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Row(children: [
                                    Icon(statusIcon,
                                        color: statusColor, size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(statusText,
                                          style: TextStyle(
                                              color: statusColor,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500)),
                                    ),
                                  ]),
                                );
                              },
                            ),
                            const SizedBox(height: 4),
                            
                            // ── Note about auto stock status ──
                            Row(
                              children: [
                                Icon(Icons.info_outline,
                                    size: 12, color: _NB.textGrey),
                                const SizedBox(width: 4),
                                const Text(
                                  'Stock status is automatically determined by quantity',
                                  style: TextStyle(
                                      fontSize: 10, color: _NB.textGrey),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // ── Submit Button ──
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _NB.orange,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _loading ? null : _saveProduct,
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isEdit
                                            ? Icons.check_circle_outline
                                            : Icons.add_circle_outline,
                                        color: Colors.white, size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        isEdit
                                            ? 'Update Product'
                                            : 'Add Product',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),

                        // ── Cancel Button (Edit mode) ──
                        if (isEdit) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: _NB.border),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                foregroundColor: _NB.textGrey,
                              ),
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Product List (Add mode only) ──
                if (!isEdit) ...[
                  _sectionHeader('My Products', Icons.storefront_outlined),
                  _productList(),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}