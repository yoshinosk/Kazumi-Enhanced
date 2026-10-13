import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:kazumi/bean/dialog/dialog.dart';
import 'package:kazumi/bean/widget/collect_button.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/pages/info/rating_detail_sheet.dart';
import 'package:skeletonizer/skeletonizer.dart';

// 视频卡片 - 水平布局
class BangumiInfoCardV extends StatefulWidget {
  const BangumiInfoCardV({
    super.key,
    required this.bangumiItem,
    required this.isLoading,
    required this.showRating,
  });

  final BangumiItem bangumiItem;
  final bool isLoading;
  final bool showRating;

  @override
  State<BangumiInfoCardV> createState() => _BangumiInfoCardVState();
}

class _BangumiInfoCardVState extends State<BangumiInfoCardV> {
  bool get _canOpenRatingDetail =>
      widget.showRating &&
      !widget.isLoading &&
      widget.bangumiItem.votes > 0;

  void _openRatingDetail() {
    showRatingDetailSheet(context, bangumiItem: widget.bangumiItem);
  }

  String get _title => widget.bangumiItem.nameCn.trim().isEmpty
      ? widget.bangumiItem.name
      : widget.bangumiItem.nameCn;

  Future<void> _copyTitle() async {
    try {
      await Clipboard.setData(ClipboardData(text: _title));
      if (mounted) KazumiDialog.showToast(message: '标题已复制');
    } catch (error) {
      if (mounted) KazumiDialog.showToast(message: '复制失败，请重试');
    }
  }

  Widget get voteBarChart {
    return Flexible(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '  评分透视:',
          ),
          SizedBox(height: 16),
          AspectRatio(
            aspectRatio: 2,
            child: RatingDistributionChart(bangumiItem: widget.bangumiItem),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      constraints: BoxConstraints(maxWidth: 950),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _title.trim().isEmpty ? null : _copyTitle,
            child: Text(
              _title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: AspectRatio(
                    aspectRatio: 0.65,
                    child: LayoutBuilder(builder: (context, boxConstraints) {
                      final double maxWidth = boxConstraints.maxWidth;
                      final double maxHeight = boxConstraints.maxHeight;
                      return Hero(
                        transitionOnUserGestures: true,
                        flightShuttleBuilder:
                            NetworkImgLayer.heroFlightShuttleBuilder,
                        tag: widget.bangumiItem.id,
                        child: NetworkImgLayer(
                          src: widget.bangumiItem.images['large'] ?? '',
                          width: maxWidth,
                          height: maxHeight,
                          fadeInDuration: const Duration(milliseconds: 0),
                          fadeOutDuration: const Duration(milliseconds: 0),
                        ),
                      );
                    }),
                  ),
                ),
                SizedBox(width: 16),
                Flexible(
                  child: Skeletonizer(
                    enabled: widget.isLoading,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Shrink under large system font so the collect button
                        // stays inside the fixed-height card.
                        Flexible(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.only(bottom: 8),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.topLeft,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '放送开始:',
                                  ),
                                  Text(
                                    widget.bangumiItem.airDate == ''
                                        ? '2000-11-11' // Skeleton Loader 占位符
                                        : widget.bangumiItem.airDate,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _canOpenRatingDetail
                                        ? _openRatingDetail
                                        : null,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.showRating
                                              ? '${widget.bangumiItem.votes} 人评分:'
                                              : '*** 人评分:',
                                        ),
                                        if (widget.isLoading)
                                          // Skeleton Loader 占位符
                                          Text(
                                            '10.0 ********',
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                          ),
                                        if (!widget.isLoading)
                                          Row(
                                            children: [
                                              Text(
                                                widget.showRating
                                                    ? '${widget.bangumiItem.ratingScore}'
                                                    : '***',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              RatingBarIndicator(
                                                itemCount: 5,
                                                rating: widget.showRating
                                                    ? widget.bangumiItem
                                                            .ratingScore
                                                            .toDouble() /
                                                        2
                                                    : 0,
                                                itemBuilder: (context, index) =>
                                                    Icon(
                                                  Icons.star_rounded,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                ),
                                                itemSize: 20.0,
                                              ),
                                            ],
                                          ),
                                        SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Text(
                                              'Bangumi Ranked:',
                                            ),
                                            if (_canOpenRatingDetail) ...[
                                              const SizedBox(width: 4),
                                              Icon(
                                                Icons.chevron_right,
                                                size: 18,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ],
                                          ],
                                        ),
                                        Text(
                                          widget.showRating
                                              ? (widget.bangumiItem.rank > 0
                                                  ? '#${widget.bangumiItem.rank}'
                                                  : '未上榜')
                                              : '***',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          height: 40,
                          child: CollectButton.extend(
                            bangumiItem: widget.bangumiItem,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.showRating &&
                    MediaQuery.sizeOf(context).width >=
                        LayoutBreakpoint.compact['width']! &&
                    !widget.isLoading)
                  voteBarChart,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
