// -*- C++ -*-

#ifndef ocropus_clstmhl_
#define ocropus_clstmhl_

#include "pstring.h"
#include "clstm.h"
#include "extras.h"
#include <memory>
#include <string>
#include <vector>

namespace ocropus {

struct CharPrediction {
  int i;
  int x;
  wchar_t c;
  float p;
};

struct CLSTMText {
  Network net;
  int nclasses = -1;
  int iclasses = -1;
  int neps = 3;
  Sequence targets;
  Sequence aligned;
  void setLearningRate(float lr, float mom) { net->setLearningRate(lr, mom); }
  void load(const std::string &fname) {
    net = load_net(fname);
    nclasses = net->codec.size();
    iclasses = net->icodec.size();
    neps = net->attr.get("neps");
  }
  void save(const std::string &fname) { save_net(fname, net); }
  void createBidi(const std::vector<int> &icodec, const std::vector<int> codec,
                  int nhidden) {
    // This is just the simplest case of creating a network. For more complex
    // networks, create them outside and assign them to "net".
    iclasses = icodec.size();
    nclasses = codec.size();
    net = make_net("bidi", {{"ninput", (int)icodec.size()},
                            {"noutput", (int)codec.size()},
                            {"nhidden", nhidden}});
    net->attr.set("neps", neps);
    net->icodec.set(icodec);
    net->codec.set(codec);
  }
  void setInputs(const std::wstring &s) {
    Classes cs;
    net->icodec.encode(cs, s);
    Sequence &seq = net->inputs;
    int d = net->ninput();
    seq.clear();
    seq.resize(cs.size() * (neps + 1) + neps, d, 1);
    int index = 0;
    for (int i = 0; i < neps; i++) seq[index++].clear();
    for (int pos = 0; pos < cs.size(); pos++) {
      seq[index].clear();
      seq[index++].v(cs[pos], 0) = 1.0;
      for (int i = 0; i < neps; i++) seq[index++].clear();
    }
    assert(index == seq.size());
    seq.check();
  }
  std::wstring train(const std::wstring &in, const std::wstring &target) {
    setInputs(in);
    net->forward();
    Classes transcript;
    net->codec.encode(transcript, target);
    mktargets(targets, transcript, nclasses);
    ctc_align_targets(aligned, net->outputs, targets);
    for (int t = 0; t < aligned.size(); t++)
      net->outputs[t].d = aligned[t].v - net->outputs[t].v;
    net->backward();
    net->update();
    Classes output_classes;
    trivial_decode(output_classes, net->outputs);
    return net->codec.decode(output_classes);
  }
  std::wstring predict(const std::wstring &in) {
    setInputs(in);
    net->forward();
    Classes output_classes;
    trivial_decode(output_classes, net->outputs);
    return net->codec.decode(output_classes);
  }
  void train_utf8(const std::string &in, const std::string &target) {
    train(utf8_to_utf32(in), utf8_to_utf32(target));
  }
  std::string aligned_utf8() {
    Classes outputs;
    trivial_decode(outputs, aligned);
    std::wstring temp = net->codec.decode(outputs);
    return utf32_to_utf8(temp);
  }
  std::string predict_utf8(const std::string &in) {
    return utf32_to_utf8(predict(utf8_to_utf32(in)));
  }
  void get_outputs(mdarray<float> &outputs) {
    Sequence &o = net->outputs;
    outputs.resize(int(o.size()), int(o[0].rows()));
    for (int t = 0; t < outputs.dim(0); t++)
      for (int c = 0; c < outputs.dim(1); c++)
        outputs(t, c) = net->outputs[t].v(c, 0);
  }
};

struct CLSTMOCR {
  unique_ptr<INormalizer> normalizer;
  Network net;
  int target_height = 48;
  int nclasses = -1;
  Sequence aligned, targets;
  mdarray<float> image;
  void setLearningRate(float lr, float mom) { net->setLearningRate(lr, mom); }
  void load(const std::string &fname) {
    net = load_net(fname);
    nclasses = net->codec.size();
    normalizer.reset(make_CenterNormalizer());
    normalizer->target_height = target_height;
  }
  void save(const std::string &fname) { save_net(fname, net); }
  void createBidi(const std::vector<int> codec, int nhidden) {
    nclasses = codec.size();
    net = make_net("bidi", {{"ninput", target_height},
                            {"noutput", nclasses},
                            {"nhidden", nhidden}});
    net->initialize();
    net->codec.set(codec);
    normalizer.reset(make_CenterNormalizer());
    normalizer->target_height = target_height;
  }
  std::wstring train(mdarray<float> &raw, const std::wstring &target) {
    normalizer->measure(raw);
    normalizer->normalize(image, raw);
    assign(net->inputs, image);
    net->forward();
    Classes transcript;
    net->codec.encode(transcript, target);
    mktargets(targets, transcript, nclasses);
    ctc_align_targets(aligned, net->outputs, targets);
    for (int t = 0; t < aligned.size(); t++)
      net->outputs[t].d = aligned[t].v - net->outputs[t].v;
    net->backward();
    net->update();
    Classes outputs;
    trivial_decode(outputs, net->outputs);
    return net->codec.decode(outputs);
  }
  std::string aligned_utf8() {
    Classes outputs;
    trivial_decode(outputs, aligned);
    std::wstring temp = net->codec.decode(outputs);
    return utf32_to_utf8(temp);
  }
  std::string train_utf8(mdarray<float> &raw, const std::string &target) {
    return utf32_to_utf8(train(raw, utf8_to_utf32(target)));
  }
  std::wstring predict(mdarray<float> &raw, vector<int> *where = 0) {
    normalizer->measure(raw);
    normalizer->normalize(image, raw);
    assign(net->inputs, image);
    net->forward();
    Classes outputs;
    trivial_decode(outputs, net->outputs, 0, where);
    return net->codec.decode(outputs);
  }
  void predict(vector<CharPrediction> &preds, mdarray<float> &raw) {
    normalizer->measure(raw);
    normalizer->normalize(image, raw);
    assign(net->inputs, image);
    net->forward();
    Classes outputs;
    vector<int> where;
    trivial_decode(outputs, net->outputs, 0, &where);
    preds.clear();
    for (int i = 0; i < outputs.size(); i++) {
      int t = where[i];
      int cls = outputs[i];
      wchar_t c = net->codec.decode(outputs[i]);
      float p = net->outputs[t].v(cls, 0);
      CharPrediction pred{i, t, c, p};
      preds.push_back(pred);
    }
  }
  std::string predict_utf8(mdarray<float> &raw) {
    return utf32_to_utf8(predict(raw));
  }
  void get_outputs(mdarray<float> &outputs) {
    Sequence &o = net->outputs;
    outputs.resize(int(o.size()), int(o[0].rows()));
    for (int t = 0; t < outputs.dim(0); t++)
      for (int c = 0; c < outputs.dim(1); c++)
        outputs(t, c) = net->outputs[t].v(c, 0);
  }
};
}

#endif
