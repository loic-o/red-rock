(function (M) {
  const util = {};

  // swiped from Chart.js utils: https://www.chartjs.org/docs/latest/samples/utils.html
  util.valueOrDefault = function (value, defaultValue) {
    return typeof value == 'undefined' ? defaultValue : value;
  }

  var _seed = Date.now();

  util.rand = function (min, max) {
    min = util.valueOrDefault(min, 0);
    max = util.valueOrDefault(max, 0);
    _seed = (_seed * 9301 + 49297) % 233280;
    return min + (_seed / 233280) * (max - min);
  }

  util.numbers = function (config) {
    var cfg = config || {};
    var min = util.valueOrDefault(cfg.min, 0);
    var max = util.valueOrDefault(cfg.max, 100);
    var from = util.valueOrDefault(cfg.from, []);
    var count = util.valueOrDefault(cfg.count, 8);
    var decimals = util.valueOrDefault(cfg.decimals, 8);
    var continuity = util.valueOrDefault(cfg.continuity, 1);
    var dfactor = Math.pow(10, decimals) || 0;
    var data = [];
    var i, value;

    for (i = 0; i < count; ++i) {
      value = (from[i] || 0) + util.rand(min, max);
      if (util.rand() <= continuity) {
        data.push(Math.round(dfactor * value) / dfactor);
      } else {
        data.push(null);
      }
    }
    return data;
  }

  M.util = util;
})(this);

