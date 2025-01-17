// -*- C++ -*-

%{
#pragma GCC diagnostic ignored "-Wstrict-aliasing"
#pragma GCC diagnostic ignored "-Wuninitialized"
#pragma GCC diagnostic ignored "-Wunused-but-set-variable"
#define NPY_NO_DEPRECATED_API NPY_1_7_API_VERSION
%}

%module(docstring="C-version of the ocropy LSTM implementation") clstm;
%feature("autodoc",1);
%include "typemaps.i"
%include "std_string.i"
%include "std_wstring.i"
%include "std_shared_ptr.i"
%include "std_vector.i"
%shared_ptr(ITrainable)
%shared_ptr(INetwork)
#ifdef SWIGPYTHON
%include "cstring.i"
#endif

%{
#include <memory>
#include <iostream>
#include "clstm.h"
using namespace ocropus;
using namespace std;
%}

typedef float Float;
using std::string;

%inline %{
const char *hgversion = HGVERSION;
%}

#ifdef SWIGPYTHON
%exception {
    try {
        $action
    }
    catch(const char *s) {
        PyErr_SetString(PyExc_IndexError,s);
        return NULL;
    }
    catch(...) {
        PyErr_SetString(PyExc_IndexError,"unknown exception in iulib");
        return NULL;
    }
}
#endif

%{
#include "numpy/arrayobject.h"

%}

%init %{
import_array();
%}

/* create simple interface definitions for the built-in Sequence and Vec types */

struct Classes {
    Classes();
    ~Classes();
    %rename(__getitem__) operator[];
    int operator[](int i);
    int size();
    void resize(int);
};
%extend Classes {
    void __setitem__(int i,int value) {
        (*$self)[i] = value;
    }
}

struct Vec {
    Vec();
    Vec(int);
    %rename(__getitem__) operator[];
    float operator[](int i);
    int size();
};
%extend Vec {
    void __setitem__(int i,float value) {
        (*$self)[i] = value;
    }
}

struct Mat {
    Mat();
    Mat(int,int);
    %rename(__getitem__) operator();
    float operator()(int i,int j);
    int rows();
    int cols();
};
%extend Mat {
    void setValue(int i,int j,float value) {
        (*$self)(i,j) = value;
    }
}

struct Batch : Mat {
  Mat d;
};
typedef Batch Params;


struct Sequence {
    Sequence();
    ~Sequence();
    int size();
    %rename(__getitem__) operator[];
    Batch &operator[](int i);
};
%extend Sequence {
    int length() {
        return $self->size();
    }
    int depth() {
        if($self->size()==0) return -1;
        return (*$self)[0].rows();
    }
    int batchsize() {
        if($self->size()==0) return -1;
        return (*$self)[0].cols();
    }
    void assign(Sequence &other) {
        $self->resize(other.size());
        for(int t=0;t<$self->size();t++)
            (*$self)[t] = other[t];
    }
}

struct Assoc {
  string get(string key);
  string get(string key, string dflt);
  void set(string key, string dflt);
};

struct Codec {
  std::vector<int> codec;
  int size() { return codec.size(); }
  void set(const vector<int> &data);
  wchar_t decode(int cls);
  std::wstring decode(Classes &cs);
  void encode(Classes &cs, const std::wstring &s);
private:
  void operator=(const Codec &);
};

struct INetwork;
typedef std::shared_ptr<INetwork> Network;
%template(vectornet) std::vector<std::shared_ptr<INetwork> >;

struct INetwork {
    string kind;
    Assoc attr;
    virtual void setLearningRate(Float lr, Float momentum) = 0;
    virtual void forward() = 0;
    virtual void backward() = 0;
    virtual void update() = 0;
    virtual void initialize();
    virtual ~INetwork();
    Sequence inputs;
    Sequence outputs;
    std::vector<std::shared_ptr<INetwork> > sub;
    Codec codec;
    Codec icodec;
    virtual int ninput();
    virtual int noutput();
    virtual void add(std::shared_ptr<INetwork> net);
};

void set_inputs(INetwork *net, Sequence &inputs);
void set_targets(INetwork *net, Sequence &targets);
void set_classes(INetwork *net, Classes &classes);
void mktargets(Sequence &seq, Classes &targets, int ndim);

std::shared_ptr<INetwork> make_layer(string);
std::shared_ptr<INetwork> make_net_init(string,string);

%rename(seq_forward) forward_algorithm;
void forward_algorithm(Mat &lr,Mat &lmatch,double skip=-5.0);
%rename(seq_forwardbackward) forwardbackward;
void forwardbackward(Mat &both,Mat &lmatch);
%rename(seq_ctc_align) ctc_align_targets;
void ctc_align_targets(Sequence &posteriors,Sequence &outputs,Sequence &targets);
void mktargets(Sequence &seq, Classes &targets, int ndim);

void save_net(const string &file, Network net);
Network load_net(const string &file);

%rename(network_info) network_info_as_strings;

%inline %{
int string_edit_distance(string a, string b) {
    return levenshtein(a, b);
}

string network_info_as_string(Network net) {
    string result = "";
    walk_networks(net, [&result] (string s, INetwork *net) {
        double lr = net->attr.get("learning_rate","-1");
        double momentum = net->attr.get("momentum","-1");
        result += s + ": " + to_string(lr);
        result += string(" ") + to_string(momentum);
        result += string(" ") + to_string(net->ninput());
        result += string(" ") + to_string(net->noutput());
        result += "\n";
    });
    return result;
}

string sequence_info(Sequence &seq) {
    string result = "";
    result += to_string(seq.size());
    result += string(":") + (seq.size()>0?to_string(seq[0].rows()):"*");
    result += string(":") + (seq.size()>0?to_string(seq[0].cols()):"*");
    double lo = 1e99, hi = -1e99;
    for (int t=0;t<seq.size(); t++) {
        lo = fmin(lo, seq[t].v.minCoeff());
        hi = fmax(hi, seq[t].v.maxCoeff());
    }
    result += "[" + to_string(lo) + "," + to_string(hi) + "]";
    return result;
}

%}

#ifdef SWIGPYTHON
%{
template <class T, int TYPENUM>
struct NumPyArray {
    PyArrayObject *obj = 0;
    NumPyArray() {}
    NumPyArray(PyObject *object_) {
        if(!object_) throw "null pointer";
        if(!PyArray_Check(object_))
            throw "expected a numpy array";
        obj = (PyArrayObject *)object_;
        Py_INCREF(obj);
        valid();
    }
    NumPyArray(NumPyArray<T,TYPENUM> &other) {
        Py_INCREF(other.obj);
        Py_DECREF(obj);
        obj = other.obj;
    }
    NumPyArray(int d0, int d1=0, int d2=0, int d3=0) {
        npy_intp ndims[] = {d0, d1, d2, d3, 0};
        int rank = 0;
        while (ndims[rank]) rank++;
        obj = PyArray_SimpleNew(rank, ndims, TYPENUM);
        valid();
    }
    ~NumPyArray() {
        Py_DECREF(obj);
        obj = 0;
    }
    void operator=(NumPyArray<T,TYPENUM> &other) {
        Py_INCREF(other.obj);
        Py_DECREF(obj);
        obj = other.obj;
    }
    void valid() {
        if (!obj)
            throw "no array set";
        if(PyArray_TYPE(obj)!=TYPENUM)
            throw "wrong numpy array type";
        if((PyArray_FLAGS(obj)&NPY_ARRAY_C_CONTIGUOUS)==0)
            throw "expected contiguous array";
    }
    int rank() {
        valid();
        return PyArray_NDIM(obj);
    }
    int dim(int i) {
        valid();
        return PyArray_DIM(obj,i);
    }
    int size() {
        valid();
        return PyArray_SIZE(obj);
    }
    void resize(int d0, int d1=0, int d2=0, int d3=0) {
        npy_intp ndims[] = {d0, d1, d2, d3, 0};
        int rank = 0;
        while (ndims[rank]) rank++;
        PyArray_Dims dims = { ndims, rank };
        if (PyArray_Resize(obj, &dims, 0, NPY_CORDER)==nullptr)
            throw "resize failed";
    }
    T &operator()(int i) {
        assert(rank()==1);
        assert(unsigned(i)<unsigned(dim(0)));
        T *data = (T*)PyArray_DATA(obj);
        return data[i];
    }
    T &operator()(int i,int j) {
        assert(rank()==2);
        assert(unsigned(i)<unsigned(dim(0)));
        assert(unsigned(j)<unsigned(dim(1)));
        T *data = (T*)PyArray_DATA(obj);
        return data[i*dim(1)+j];
    }
    T &operator()(int i,int j,int k) {
        assert(rank()==3);
        assert(unsigned(i)<unsigned(dim(0)));
        assert(unsigned(j)<unsigned(dim(1)));
        assert(unsigned(k)<unsigned(dim(2)));
        T *data = (T*)PyArray_DATA(obj);
        return data[(i*dim(1)+j)*dim(2)+k];
    }
    T &operator()(int i,int j,int k,int l) {
        assert(rank()==4);
        assert(unsigned(i)<unsigned(dim(0)));
        assert(unsigned(j)<unsigned(dim(1)));
        assert(unsigned(k)<unsigned(dim(2)));
        assert(unsigned(l)<unsigned(dim(3)));
        T *data = (T*)PyArray_DATA(obj);
        return data[((i*dim(1)+j)*dim(2)+k)*dim(3)+l];
    }
    T *data() {
        valid();
        return (T*)PyArray_DATA(obj);
    }
    void copyTo(T *dest) {
        valid();
        T *data = (T*)PyArray_DATA(obj);
        int N = size();
        for(int i=0; i<N; i++) dest[i] = data[i];
    }
};

typedef NumPyArray<float, NPY_FLOAT> npa_float;
%}

%inline %{
void mat_of_array(Mat &a,PyObject *object_) {
    npa_float np(object_);
    if(np.rank()!=2) throw "rank must be 2";
    int N = np.dim(0);
    int d = np.dim(1);
    a.resize(N,d);
    for(int t=0;t<N;t++)
        for(int i=0;i<d;i++)
            a(t,i) = np(d,i);
}

void array_of_mat(PyObject *object_,Mat &a) {
    npa_float np(object_);
    if(np.rank()!=2) throw "rank must be 2";
    int N = a.rows();
    int d = a.cols();
    np.resize(N,d);
    for(int t=0;t<N;t++)
        for(int i=0;i<d;i++)
            np(t,i) = a(t,i);
}

void sequence_of_array(Sequence &a,PyObject *object_) {
    npa_float np(object_);
    if(np.rank()!=3) throw "rank must be 3";
    int N = np.dim(0);
    int d = np.dim(1);
    int bs = np.dim(2);
    a.resize(N);
    for(int t=0;t<N;t++) {
        a[t].resize(d,bs);
        for(int i=0; i<d; i++)
            for(int b=0; b<bs; b++)
                a[t].v(i,b) = np(t,i,b);
    }
}

void d_sequence_of_array(Sequence &a,PyObject *object_) {
    npa_float np(object_);
    if(np.rank()!=3) throw "rank must be 3";
    int N = np.dim(0);
    int d = np.dim(1);
    int bs = np.dim(2);
    if (a.size() != N) throw "size mismatch";
    for(int t=0;t<N;t++) {
        a[t].d.resize(d,bs);
        for(int i=0; i<d; i++)
            for(int b=0; b<bs; b++)
                a[t].d(i,b) = np(t,i,b);
    }
}

void array_of_sequence(PyObject *object_,Sequence &a) {
    npa_float np(object_);
    int N = a.size();
    if (N==0) throw "empty sequence";
    int d = a[0].rows();
    if (d==0) throw "empty feature vector";
    int bs = a[0].cols();
    if (bs==0) throw "empty batch";
    np.resize(N,d,bs);
    for(int t=0; t<N; t++) {
        for(int i=0; i<d; i++)
            for(int b=0; b<bs; b++)
                np(t,i,b) = a[t].v(i,b);
    }
}

void array_of_d_sequence(PyObject *object_,Sequence &a) {
    npa_float np(object_);
    int N = a.size();
    if (N==0) throw "empty sequence";
    int d = a[0].rows();
    if (d==0) throw "empty feature vector";
    int bs = a[0].cols();
    if (bs==0) throw "empty batch";
    np.resize(N,d,bs);
    for(int t=0; t<N; t++) {
        for(int i=0; i<d; i++)
            for(int b=0; b<bs; b++)
                np(t,i,b) = a[t].d(i,b);
    }
}
%}

%pythoncode %{
import numpy

def Sequence_array(self):
    a = numpy.zeros(1,'f')
    array_of_sequence(a, self)
    return a
Sequence.array = Sequence_array

def Sequence_aset(self, a):
    sequence_of_array(self, a)
Sequence.aset = Sequence_aset

def Sequence_darray(self):
    a = numpy.zeros(1,'f')
    array_of_d_sequence(a, self)
    return a
Sequence.darray = Sequence_darray

def Sequence_dset(self, a):
    d_sequence_of_array(self, a)
Sequence.dset = Sequence_dset

def ctcalign(outputs_,targets_):
    outputs = Sequence()
    targets = Sequence()
    outputs.aset(outputs_)
    targets.aset(targets_)
    posteriors = Sequence()
    seq_ctc_align(posteriors,outputs,targets)
    return posteriors.array()
%}
#endif
