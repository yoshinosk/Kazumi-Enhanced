import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_search_response.dart';
import 'package:kazumi/pages/player/danmaku_axis_dialog.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/request/apis/danmaku_api.dart';

/// 弹幕检索与切换流程：输入关键词 → 检索番剧 → 选择分集 → 绑定弹幕。
///
/// 与 [PlayerDanmakuController.getDanDanmakuByEpisodeID] 配套使用，
/// 切换后会把当前绑定的番剧/分集信息写入 controller 供弹幕面板展示。
Future<void> showDanmakuSwitchDialog({
  required PlayerController playerController,
  required VideoPageController videoPageController,
  String initialKeyword = '',
}) {
  String searchKeyword = initialKeyword;
  return KazumiDialog.show(
    builder: (context) {
      return AlertDialog(
        title: const Text('弹幕检索'),
        content: TextFormField(
          initialValue: searchKeyword,
          decoration: const InputDecoration(
            hintText: '番剧名',
          ),
          onChanged: (value) => searchKeyword = value,
          onFieldSubmitted: (keyword) {
            _searchDanmakuAndShowResult(
              playerController: playerController,
              videoPageController: videoPageController,
              keyword: keyword,
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              KazumiDialog.dismiss();
            },
            child: Text(
              '取消',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          TextButton(
            onPressed: () {
              _searchDanmakuAndShowResult(
                playerController: playerController,
                videoPageController: videoPageController,
                keyword: searchKeyword,
              );
            },
            child: const Text(
              '提交',
            ),
          ),
        ],
      );
    },
  );
}

/// 直接展示某部番剧（弹弹 Play [bangumiId]）的分集列表，点选即可切换弹幕，
/// 也可跳转到关键词检索绑定其他番剧。
Future<void> showDanmakuEpisodePickerDialog({
  required PlayerController playerController,
  required VideoPageController videoPageController,
  required int bangumiId,
  required String animeTitle,
}) async {
  KazumiDialog.showLoading(msg: '分集列表加载中');
  DanmakuEpisodeResponse danmakuEpisodeResponse;
  try {
    danmakuEpisodeResponse =
        await DanmakuApi.getDanDanEpisodesByDanDanBangumiID(bangumiId);
  } catch (e) {
    KazumiDialog.dismiss();
    KazumiDialog.showToast(message: '分集列表获取失败: ${e.toString()}');
    showDanmakuSwitchDialog(
      playerController: playerController,
      videoPageController: videoPageController,
      initialKeyword: animeTitle,
    );
    return;
  }
  KazumiDialog.dismiss();
  if (danmakuEpisodeResponse.episodes.isEmpty) {
    KazumiDialog.showToast(message: '该番剧暂无可用的弹幕分集');
    showDanmakuSwitchDialog(
      playerController: playerController,
      videoPageController: videoPageController,
      initialKeyword: animeTitle,
    );
    return;
  }
  await KazumiDialog.show(builder: (context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Text(
                animeTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: danmakuEpisodeResponse.episodes.length,
                itemBuilder: (context, index) {
                  final episode = danmakuEpisodeResponse.episodes[index];
                  final bool isCurrent = episode.episodeId ==
                          playerController.danmaku.danmakuEpisodeId ||
                      episode.episodeTitle ==
                          playerController.danmaku.danmakuEpisodeTitle;
                  return ListTile(
                    selected: isCurrent,
                    title: Text(
                      episode.episodeTitle,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isCurrent
                        ? Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: () {
                      KazumiDialog.dismiss();
                      bindDanmakuToEpisode(
                        playerController: playerController,
                        videoPageController: videoPageController,
                        animeTitle: animeTitle,
                        episode: episode,
                      );
                    },
                  );
                },
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: TextButton(
                  onPressed: () {
                    KazumiDialog.dismiss();
                    showDanmakuSwitchDialog(
                      playerController: playerController,
                      videoPageController: videoPageController,
                      initialKeyword: animeTitle,
                    );
                  },
                  child: const Text('搜索其他番剧'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  });
}

/// 绑定指定番剧的指定分集弹幕，成功后开启弹幕并提示。
Future<void> bindDanmakuToEpisode({
  required PlayerController playerController,
  required VideoPageController videoPageController,
  required String animeTitle,
  required DanmakuEpisode episode,
}) async {
  try {
    videoPageController.cancelAutomaticDanmakuLoad();
    final hasDanmakus = await playerController.danmaku.getDanDanmakuByEpisodeID(
        episode.episodeId,
        animeTitle: animeTitle,
        episodeTitle: episode.episodeTitle);
    if (hasDanmakus) {
      playerController.danmaku.setDanmakuEnabled(true);
      KazumiDialog.showToast(message: '弹幕切换成功');
      await checkDanmakuAxisAlignment(
        playerController: playerController,
        videoPageController: videoPageController,
        danmakus: playerController.danmaku.danDanmakus.values
            .expand((danmakus) => danmakus)
            .toList(),
        shouldProceed: () =>
            playerController.danmaku.danmakuEpisodeId == episode.episodeId,
      );
    } else {
      playerController.danmaku.setDanmakuEnabled(false);
      KazumiDialog.showToast(message: '未找到弹幕内容');
    }
  } catch (e) {
    KazumiDialog.showToast(message: '弹幕切换失败');
  }
}

Future<void> _searchDanmakuAndShowResult({
  required PlayerController playerController,
  required VideoPageController videoPageController,
  required String keyword,
}) async {
  KazumiDialog.dismiss();
  KazumiDialog.showLoading(msg: '弹幕检索中');
  DanmakuSearchResponse danmakuSearchResponse;
  try {
    danmakuSearchResponse = await DanmakuApi.getDanmakuSearchResponse(keyword);
  } catch (e) {
    KazumiDialog.dismiss();
    KazumiDialog.showToast(message: '弹幕检索错误: ${e.toString()}');
    return;
  }
  KazumiDialog.dismiss();
  if (danmakuSearchResponse.animes.isEmpty) {
    KazumiDialog.showToast(message: '未找到匹配结果');
    return;
  }
  await KazumiDialog.show(builder: (context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          shrinkWrap: true,
          children: danmakuSearchResponse.animes.map((danmakuInfo) {
            return ListTile(
              title: Text(danmakuInfo.animeTitle),
              onTap: () async {
                KazumiDialog.dismiss();
                KazumiDialog.showLoading(msg: '弹幕检索中');
                DanmakuEpisodeResponse danmakuEpisodeResponse;
                try {
                  danmakuEpisodeResponse =
                      await DanmakuApi.getDanDanEpisodesByDanDanBangumiID(
                          danmakuInfo.animeId);
                } catch (e) {
                  KazumiDialog.dismiss();
                  KazumiDialog.showToast(message: '弹幕检索错误: ${e.toString()}');
                  return;
                }
                KazumiDialog.dismiss();
                if (danmakuEpisodeResponse.episodes.isEmpty) {
                  KazumiDialog.showToast(message: '未找到匹配结果');
                  return;
                }
                await KazumiDialog.show(builder: (context) {
                  return Dialog(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: ListView(
                        shrinkWrap: true,
                        children:
                            danmakuEpisodeResponse.episodes.map((episode) {
                          return ListTile(
                            title: Text(episode.episodeTitle),
                            onTap: () {
                              KazumiDialog.dismiss();
                              bindDanmakuToEpisode(
                                playerController: playerController,
                                videoPageController: videoPageController,
                                animeTitle: danmakuInfo.animeTitle,
                                episode: episode,
                              );
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  );
                });
              },
            );
          }).toList(),
        ),
      ),
    );
  });
}
